# Changelog

All notable changes to this project will be documented in this file.

## Release 0.2.0

This release updates the module metadata for the new Forge namespace and GitHub
ownership, and prepares the module for publishing as `joy-kubecm`.

**Breaking/Notable Changes**

* The Forge module name is now `joy-kubecm`. Update Bolt and Puppetfile
  references that still use `jtl-kubecm`.

**Features**

* When using `render_to`, Helm templates are now rendered with
  `--kube-version` based on the target cluster's server version from
  `kubectl version -o yaml`. This improves rendered output for charts with
  Kubernetes-version-specific templates.

**Maintenance**

* Update the module to the PDK 3.6.1 template and refresh development
  dependencies for newer Ruby and Puppet toolchains.
* Update CI to use the current PDK job image format.
* Simplify the README installation instructions to use `bolt module add`.

## Release 0.1.1

Remove file accidentally included in previous release.

## Release 0.1.0

Initial release including fully functional deploy plan originally from
[Nest](https://github.com/jameslikeslinux/puppet-nest). Parameter names have
been changed to be a little more generic, and the code has been significantly
refactored for public consumption. Added tests and documentation.

**Features**

* Deploy charts with custom resources, values, and patches.
* Integrate into your own project with parameters to customize lookups.
* Automatically generate Helm chart to manage bare resources.
* Manage multiple charts as one release with subcharts.

**Bugfixes**

* Build intermediate files in separate directories to avoid conflicts.

**Known Issues**

* This project does not currently run on Windows.
