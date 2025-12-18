# @summary Puppet entrypoint for the kubecm::deploy plan
#
# This defines the following variables for use in your Hiera hierarchy
# and data, and declares other classes for your own custom variables.
#
#   * kubecm::deploy::release
#   * kubecm::deploy::chart
#   * kubecm::deploy::chart_source
#   * kubecm::deploy::namespace
#   * kubecm::deploy::parent
#   * kubecm::deploy::version
#
# @param include_key Hiera key mapping a list of custom classes to declare
# @param resources_key Hiera key mapping a hash of resources to deploy
# @param values_key Hiera key mapping a hash of values to apply to the chart
# @param patches_key Hiera key mapping a hash of Kustomize patches to apply, ordered by key.
# @param release_build_dir Deployment-specific place to compile manifests. Will be purged!
# @param remove_resources Resource keys to remove from deployment
# @param remove_patches Patch keys to remove from kustomization
# @param subchart_manifests List of already-generated subchart manifests to deploy
# @api private
class kubecm::deploy (
  String               $include_key,
  String               $resources_key,
  String               $values_key,
  String               $patches_key,
  Stdlib::Absolutepath $release_build_dir,
  Array[String]        $remove_resources   = [],
  Array[String]        $remove_patches     = [],
  Array[String]        $subchart_manifests = [],
) {
  # Bring plan variables into class scope for lookups
  # (class parameters can't be used in lookups until after it's fully loaded)
  # lint:ignore:top_scope_facts
  $release      = $::release
  $chart        = $::chart
  $chart_source = $::chart_source
  $namespace    = pick_default($::namespace, 'default')
  $parent       = $::parent
  $version      = $::version
  # lint:endignore

  # Include custom classes that define other variables for lookups
  lookup($include_key, Array[String], 'unique', []).reverse.include

  # Perform a second lookup since the first can change the hierarchy
  lookup($include_key, Array[String], 'unique', []).reverse.include

  $resources = lookup($resources_key, Hash, 'hash', {}) - $remove_resources
  $values    = lookup($values_key, Hash, 'deep', {})
  $patches   = lookup($patches_key, Hash, 'hash', {}) - $remove_patches

  file {
    $release_build_dir:
      ensure  => directory,
      purge   => true, # clean out old files
      recurse => true; # recursively

    $subchart_manifests.map |$manifest| { "${release_build_dir}/${manifest}" }:
      ensure => present;  # don't purge subcharts

    "${release_build_dir}/helm.yaml":
      ensure => present;  # don't purge helm manifest (it will be overwritten)

    "${release_build_dir}/resources.yaml":
      content => $resources.values.flatten.map |$r| { if $r.empty { '' } else { $r.stdlib::to_yaml } }.join;

    "${release_build_dir}/values.yaml":
      content => $values.stdlib::to_yaml;

    "${release_build_dir}/kustomization.yaml":
      content => {
        'resources' => $subchart_manifests + ['resources.yaml', 'helm.yaml'],
        'patches'   => $patches.keys.sort.map |$k| { $patches[$k] }.flatten.map |$p| {
          if $p['patch'] =~ String {
            $p
          } else {
            $p + { 'patch' => $p['patch'].stdlib::to_yaml }
          }
        },
      }.stdlib::to_yaml;

    "${release_build_dir}/kustomize.sh":
      mode   => '0755',
      source => 'puppet:///modules/kubecm/kustomize.sh';
  }

  if !$chart_source {
    if $version {
      $fake_chart_version = $version
    } else {
      $fake_chart_version = '0.1.0' # just something
    }

    file {
      "${release_build_dir}/chart":
        ensure => directory;

      "${release_build_dir}/chart/Chart.yaml":
        content => {
          'apiVersion'  => 'v2',
          'name'        => $chart,
          'description' => 'KubeCM deployment',
          'type'        => 'application',
          'version'     => $fake_chart_version,
        }.stdlib::to_yaml;
    }
  } elsif $chart_source =~ Stdlib::Filesource {
    file { "${release_build_dir}/chart":
      ensure  => directory,
      recurse => true,
      source  => $chart_source,
    }
  }
}
