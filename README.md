# KubeCM: Kubernetes Configuration Management

[![pipeline status](https://gitlab.joyfullee.me/joy/kubecm/badges/main/pipeline.svg)](https://gitlab.joyfullee.me/joy/kubecm/-/commits/main)

- [Overview](#overview)
- [Features](#features)
- [Motivation](#motivation)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Usage](#usage)
  - [Deploying Applications](#deploying-applications)
  - [Configuring Deployments](#configuring-deployments)
- [Custom Resources, Values, and Patches](#custom-resources-values-and-patches)
- [YAML Plans](#yaml-plans)
  - [Example 1: Deploying Vaultwarden](#example-1-deploying-vaultwarden)
  - [Example 2: Deploying WordPress](#example-2-deploying-wordpress)
- [Troubleshooting](#troubleshooting)
  - [Using the `render_to` Parameter](#using-the-render_to-parameter)
  - [Exploring the Build Directory](#exploring-the-build-directory)
- [Contributing](#contributing)


## Overview

**KubeCM (Kubernetes Configuration Management)** empowers you to control and
deploy Kubernetes resources your way, combining the strengths of Puppet, Helm,
and Kustomize. With KubeCM, you can manage, customize, and configure Kubernetes
deployments using a hierarchical data model and YAML plans that provide clarity
and reusability.

## Features

- **Unified Management**: Deploy Helm charts, custom resources, and Kustomize
  patches under one plan.
- **Hierarchical Configuration**: Use Hiera to store, merge, and override
  configurations at multiple levels.
- **Secure Secrets**: Encrypt sensitive data using Hiera-EYAML.
- **Custom Resource Deployment**: Deploy any Kubernetes resource directly
  without requiring a Helm chart.
- **Integrated Orchestration**: Bolt-powered orchestration for on-demand or
  scheduled deployments.
- **Cloud Transition**: Leverage existing Puppet data and automation to ease
  migrations to Kubernetes.

## Motivation

Kubernetes excels at managing clusters, but it struggles with managing entire
deployments as cohesive units. Helm addresses this gap with templated "charts,"
but real-world applications often require configuration changes that Helm
templates do not expose. KubeCM steps in to bridge this gap by leveraging
Puppet's powerful configuration management features (like Hiera and Bolt) to
manage and customize Helm, Kustomize, and raw Kubernetes resources as a unified
whole.

## Getting Started

### Prerequisites

Ensure the following tools are installed and configured on a Linux system:

- **kubectl**: Kubernetes CLI for managing clusters.
- **helm**: Kubernetes package manager.
- **bolt**: Puppet orchestration tool.
- **hiera-eyaml**: Optional, for encrypted secrets.

### Installation

1. **Create a Bolt project**:

   ```bash
   mkdir acme_inc
   cd acme_inc
   bolt project init
   ```

2. **Install the module**:

   ```bash
   bolt module add joy-kubecm
   ```

### Usage

#### Deploying Applications

The following parameters in the `kubecm::deploy` plan specify key aspects of a
deployment:

- **release**: The unique name of the deployment within the Kubernetes
  namespace. Each deployment should have a distinct release name.
- **chart**: The name of the Helm chart to be used for the deployment.
- **chart\_source**: The location of the Helm chart from a repo, a local
  directory, or an OCI registry reference. This tells Helm where to retrieve
  the chart. It can also be undefined to deploy without a chart, using only
  resources from Hiera.
- **repo_url**: If using a repo reference in `chart_source` (e.g.
  `repo_name/chart_name`), the HTTP location of the Helm repository.

Use the `kubecm::deploy` plan to install applications via Helm charts.

Example:

```bash
bolt plan run kubecm::deploy release=shop chart=wordpress chart_source=oci://registry-1.docker.io/bitnamicharts/wordpress
bolt plan run kubecm::deploy release=blog chart=wordpress chart_source=oci://registry-1.docker.io/bitnamicharts/wordpress
bolt plan run kubecm::deploy release=vaultwarden chart_source=guerzon/vaultwarden repo_url=https://guerzon.github.io/vaultwarden
```

This deploys two WordPress instances ("shop" and "blog") and a Vaultwarden
instance.

#### Configuring Deployments

Configuration is managed using Hiera's hierarchical structure. Create a
`hiera.yaml` in the project directory:

```yaml
---
version: 5

defaults:
  datadir: data
  data_hash: yaml_data

hierarchy:
  - name: 'Releases'
    paths:
      - "release/%{kubecm::deploy::release}/%{kubecm::deploy::namespace}.yaml"
      - "release/%{kubecm::deploy::release}.yaml"
  - name: 'Charts'
    paths:
      - "chart/%{kubecm::deploy::chart}/%{kubecm::deploy::namespace}.yaml"
      - "chart/%{kubecm::deploy::chart}.yaml"
  - name: 'Common'
    paths:
      - 'common.yaml'
```

To provide additional customization, you can override KubeCM's default key
names for various deployment settings. These keys include:

- **include\_key**: Used to define additional Puppet classes to be included.
- **resources\_key**: Used to define Kubernetes resources to be created as part of the deployment.
- **values\_key**: Used to provide Helm chart values for the deployment.
- **patches\_key**: Used to define Kustomize patches to apply to resources.

These key names can be set in `data/common.yaml` to override the defaults as
shown below:

```yaml
---
kubecm::deploy::include_key: 'include'
kubecm::deploy::resources_key: 'resources'
kubecm::deploy::values_key: 'values'
kubecm::deploy::patches_key: 'patches'
```

This configuration allows for a more customized, DSL-like experience when
managing Kubernetes deployments with KubeCM. You can modify these key names to
avoid conflicts with other existing keys in your control repository.

## Custom Resources, Values, and Patches

**Values Examples**:

**Memory Resource Parameterization**:

This example demonstrates how to set default memory requests for Helm
deployments and override them at a namespace-specific level.

`data/chart/wordpress.yaml`

```yaml
---
memory: 200Mi

values:
  resources:
    requests:
      memory: "%{lookup('memory')}"
```

`data/chart/wordpress/test.yaml`

```yaml
---
memory: 100Mi
```

**Ingress Hostname Parameterization**:

This example shows how to set a default ingress hostname pattern for all
releases and override it for specific releases.

`data/chart/wordpress.yaml`

```yaml
---
ingress_hostname: "%{kubecm::deploy::release}.example.com"

values:
  ingress:
    enabled: true
    hostname: "%{lookup('ingress_hostname')}"
```

`data/release/shop.yaml`

```yaml
---
ingress_hostname: 'store.example.com'
```

**Vaultwarden Admin Token Hash Calculation**:

This example demonstrates how to hash the Vaultwarden admin token dynamically
and make it available as a Helm chart value.

`data/chart/vaultwarden.yaml`

```yaml
---
include:
  - 'acme_inc::vaultwarden'

admin_token: supersecuretoken # encrypt this with hiera-eyaml!

values:
  adminToken:
    value: "%{acme_inc::vaultwarden::admin_token_hash}"
```

`manifests/vaultwarden.pp`

```puppet
class acme_inc::vaultwarden {
  $admin_token = lookup('admin_token')
  $admin_token_hash = generate(
    '/bin/sh',
    '-c',
    "echo -n ${admin_token.shellquote} | argon2 `openssl rand -base64 32` -e -id -k 65540 -t 3 -p 4",
  ).chomp
}
```

**Registry Auths Example**:

This example demonstrates how to manage Docker registry authentication secrets
to be used by Kubernetes deployments.

`data/common.yaml`

```yaml
---
include:
  - 'acme_inc'

registry_tokens:
  registry.example.com: fake-token # encrypt this with hiera-eyaml!

resources:
  registry_auths:
    - apiVersion: v1
      kind: Secret
      metadata:
        name: "%{kubecm::deploy::service}-registry-auths"
        namespace: "%{kubecm::deploy::namespace}"
      data:
        .dockerconfigjson: "%{acme_inc::registry_auths_base64}"
      type: kubernetes.io/dockerconfigjson
```

`manifests/init.pp`

```puppet
class acme_inc {
  $registry_tokens = lookup('registry_tokens')
  $registry_auths_base64 = base64('encode', stdlib::to_json({
    'auths' => $registry_tokens.reduce({}) |$result, $token| {
      $result + { $token[0] => { 'auth' => base64('encode', $token[1]).chomp } }
    },
  }))
}
```

**Patch Example**

This example demonstrates how to use a Kustomize patch to modify Kubernetes
resources in place. Patches like this are useful when you need to modify
resource properties that aren't exposed as chart values, such as node affinity,
tolerations, or annotations. Patching can be especially helpful when dealing
with third-party charts where direct configuration is limited:

`data/chart/vaultwarden.yaml`

```yaml
---
node_role: special

patches:
  10-placement:
    patch:
      kind: not-important
      metadata:
        name: not-important
      spec:
        template:
          spec:
            affinity:
              nodeAffinity:
                requiredDuringSchedulingIgnoredDuringExecution:
                  nodeSelectorTerms:
                    - matchExpressions:
                      - key: "node-role.kubernetes.io/%{lookup('node_role')}"
                        operator: Exists
            tolerations:
              - key: "node-role.kubernetes.io/%{lookup('node_role')}"
                operator: Exists
                effect: NoSchedule
    targets:
      kind: (Deployment|StatefulSet|Job)
```

## YAML Plans

YAML plans provide a simple way to define deployment workflows using YAML
syntax. They enable you to automate the execution of multiple tasks, making it
easier to manage and update Kubernetes resources in a consistent manner.

YAML plans are especially useful for repeatable deployments, where you want to
ensure that all necessary steps are executed in the correct order. Below are
two example YAML plans for deploying Vaultwarden and WordPress applications.

### Example 1: Deploying Vaultwarden

This YAML plan defines a simple process to deploy the Vaultwarden application
using KubeCM's `kubecm::deploy` plan.

`plans/deploy_vaultwarden.yaml`

```yaml
---
description: 'Deploy Acme Inc Vaultwarden'

steps:
  - description: 'Deploy Vaultwarden'
    plan: kubecm::deploy
    parameters:
      release: 'vaultwarden'
      chart_source: 'guerzon/vaultwarden'
      repo_url: 'https://guerzon.github.io/vaultwarden'
```

This plan deploys the Vaultwarden release using the specified chart and
repository URL.

### Example 2: Deploying WordPress

This YAML plan defines a more flexible deployment workflow for WordPress. It
allows the user to specify which instance (either 'shop' or 'blog') should be
deployed.

`plans/deploy_wordpress.yaml`

```yaml
---
description: 'Deploy Acme Inc WordPress'

parameters:
  site:
    description: The release to deploy
    type: Enum['shop', 'blog']

steps:
  - description: 'Deploy WordPress'
    plan: kubecm::deploy
    parameters:
      release: $site
      chart: wordpress
      chart_source: oci://registry-1.docker.io/bitnamicharts/wordpress
```

This plan introduces the `parameters` block, which requires the user to specify
the site (either `shop` or `blog`) to be deployed. This is useful when you want
to reuse the same plan logic for multiple deployments.

To run these plans, you would use the following Bolt commands:

```bash
bolt plan run acme_inc::deploy_vaultwarden
bolt plan run acme_inc::deploy_wordpress site=shop
bolt plan run acme_inc::deploy_wordpress site=blog
```

These YAML plans streamline deployments, enforce consistency, and ensure
repeatable, parameterized workflows that are easy to maintain and execute.

## Troubleshooting

If you encounter issues with your deployments, KubeCM provides several tools to
help diagnose and debug problems.

### Using the `render_to` Parameter

The `render_to` parameter allows you to render the final output of the Helm or
Kustomize configuration to a local file. This is useful for verifying the
rendered Kubernetes manifests before deploying them.

Example usage:

```bash
bolt plan run kubecm::deploy release=shop chart=wordpress chart_source=oci://registry-1.docker.io/bitnamicharts/wordpress render_to=output.yaml
```

After the command runs, the rendered configuration will be saved in
`output.yaml` for review.

### Exploring the Build Directory

KubeCM generates a build directory during deployment. This directory contains
intermediate files and configurations produced during the rendering and
patching process. The build directory provides insight into the final state of
configurations before they are applied to the Kubernetes cluster.

By default, the build directory is named `build` and is created in the current
working directory.

To explore the build directory, you can navigate into it and review the files:

```bash
cd build
ls -al
```

Inside, you will find rendered manifests and debug information, which can be
invaluable when troubleshooting failed deployments or understanding how your
configurations were combined.

## Contributing

Contributions are welcome! Follow these steps to contribute:

1. **Use your fork for development**:

   Modify the `bolt-project.yaml` to use your forked repository:

   ```yaml
   modules:
     - name: kubecm
       git: <repo-url>
       ref: <branch-name>
   ```

   Then run:

   ```bash
   bolt module install
   ```

2. **Project is managed with PDK**:

   Before contributing changes back to the project, ensure that your changes
   pass PDK validation and tests:

   ```bash
   pdk validate
   pdk test unit
   ```

3. **Submit a pull request**.

---

Happy Deploying!
