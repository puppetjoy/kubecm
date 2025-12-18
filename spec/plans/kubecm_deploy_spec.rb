require 'spec_helper'
require 'bolt_spec/plans'

describe 'kubecm::deploy' do
  include BoltSpec::Plans

  before(:each) do
    BoltSpec::Plans.init
    allow_command('pwd').always_return({ 'stdout' => '/fakedir' })
    allow_command 'mkdir -p /fakedir/build/test'
    allow_apply
  end

  it 'uses the specified build_dir' do
    expect_command('pwd').not_be_called
    expect_command 'mkdir -p /mybuilddir/test'
    expect_command <<~CMD.chomp
      helm upgrade --install test /mybuilddir/test/chart \
      --post-renderer /mybuilddir/test/kustomize.sh \
      --post-renderer-args /mybuilddir/test \
      --values /mybuilddir/test/values.yaml
    CMD

    run_plan('kubecm::deploy',
      {
        'release'      => 'test',
        'build_dir'    => '/mybuilddir',
      })
  end

  it 'deploys an empty chart when chart_source is undef' do
    expect_command <<~CMD.chomp
      helm upgrade --install test /fakedir/build/test/chart \
      --post-renderer /fakedir/build/test/kustomize.sh \
      --post-renderer-args /fakedir/build/test \
      --values /fakedir/build/test/values.yaml
    CMD

    run_plan('kubecm::deploy',
      {
        'release' => 'test',
      })
  end

  it 'deploys a local chart when chart_source is an absolute path' do
    expect_command <<~CMD.chomp
      helm upgrade --install test /fakedir/build/test/chart \
      --post-renderer /fakedir/build/test/kustomize.sh \
      --post-renderer-args /fakedir/build/test \
      --values /fakedir/build/test/values.yaml
    CMD

    run_plan('kubecm::deploy',
      {
        'release'      => 'test',
        'chart_source' => '/mychart', # gets copied to /fakedir/build/test/chart
      })
  end

  it 'deploys a chart from a repo' do
    expect_command 'helm repo add fakerepo https://example.com/fakerepo'
    expect_command <<~CMD.chomp
      helm upgrade --install test fakerepo/fakechart \
      --post-renderer /fakedir/build/test/kustomize.sh \
      --post-renderer-args /fakedir/build/test \
      --values /fakedir/build/test/values.yaml
    CMD

    run_plan('kubecm::deploy',
      {
        'release'      => 'test',
        'chart_source' => 'fakerepo/fakechart',
        'repo_url'     => 'https://example.com/fakerepo',
      })
  end

  it 'deploys a chart from an oci:// URI' do
    expect_command <<~CMD.chomp
      helm upgrade --install test oci://example.com/fakerepo/fakechart \
      --post-renderer /fakedir/build/test/kustomize.sh \
      --post-renderer-args /fakedir/build/test \
      --values /fakedir/build/test/values.yaml
    CMD

    run_plan('kubecm::deploy',
      {
        'release'      => 'test',
        'chart_source' => 'oci://example.com/fakerepo/fakechart',
      })
  end

  it 'deploys a local chart from a relative path' do
    expect_command <<~CMD.chomp
      helm upgrade --install test ./mychart \
      --post-renderer /fakedir/build/test/kustomize.sh \
      --post-renderer-args /fakedir/build/test \
      --values /fakedir/build/test/values.yaml
    CMD

    run_plan('kubecm::deploy',
      {
        'release'      => 'test',
        'chart_source' => 'mychart',
      })
  end

  it 'renders a chart to a specified file' do
    version_yaml = <<~YAML.chomp
      serverVersion:
        major: "1"
        minor: "99"
    YAML
    expect_command('kubectl version -o yaml').always_return({ stdout: version_yaml })
    expect_command <<~CMD.chomp
      helm template --kube-version 1.99 \
      test /fakedir/build/test/chart \
      --post-renderer /fakedir/build/test/kustomize.sh \
      --post-renderer-args /fakedir/build/test \
      --values /fakedir/build/test/values.yaml > test.yaml
    CMD

    run_plan('kubecm::deploy',
      {
        'release'   => 'test',
        'render_to' => 'test.yaml',
      })
  end

  it 'deploys without hooks if requested' do
    expect_command <<~CMD.chomp
      helm upgrade --install test /fakedir/build/test/chart \
      --no-hooks \
      --post-renderer /fakedir/build/test/kustomize.sh \
      --post-renderer-args /fakedir/build/test \
      --values /fakedir/build/test/values.yaml
    CMD

    run_plan('kubecm::deploy',
      {
        'release' => 'test',
        'hooks'   => false,
      })
  end

  it 'deploys to the specified namespace' do
    expect_command 'mkdir -p /fakedir/build/test-ns'
    expect_command <<~CMD.chomp
      helm upgrade --install test /fakedir/build/test-ns/chart \
      --create-namespace --namespace ns \
      --post-renderer /fakedir/build/test-ns/kustomize.sh \
      --post-renderer-args /fakedir/build/test-ns \
      --values /fakedir/build/test-ns/values.yaml
    CMD

    run_plan('kubecm::deploy',
      {
        'release'   => 'test',
        'namespace' => 'ns',
      })
  end

  it 'deploys to the specified version' do
    expect_command <<~CMD.chomp
      helm upgrade --install test /fakedir/build/test/chart \
      --post-renderer /fakedir/build/test/kustomize.sh \
      --post-renderer-args /fakedir/build/test \
      --values /fakedir/build/test/values.yaml \
      --version 1.2.3
    CMD

    run_plan('kubecm::deploy',
      {
        'release' => 'test',
        'version' => '1.2.3',
      })
  end

  it 'waits for the deployment if requested' do
    expect_command <<~CMD.chomp
      helm upgrade --install test /fakedir/build/test/chart \
      --post-renderer /fakedir/build/test/kustomize.sh \
      --post-renderer-args /fakedir/build/test \
      --values /fakedir/build/test/values.yaml \
      --wait --timeout 1h
    CMD

    run_plan('kubecm::deploy',
      {
        'release' => 'test',
        'wait'    => true,
      })
  end

  it 'sleeps additional time if requested' do
    allow_any_command
    expect_out_message.with_params('Waiting 10 seconds')
    run_plan('kubecm::deploy',
      {
        'release' => 'test',
        'sleep'   => 10,
      })
  end

  it 'skips the plan entirely if requested' do
    allow_any_command.not_be_called
    allow_any_plan.not_be_called
    run_plan('kubecm::deploy',
      {
        'release' => 'test',
        'deploy'  => false,
      })
  end
end
