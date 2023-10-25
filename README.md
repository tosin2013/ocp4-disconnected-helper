# OpenShift 4 Disconnected Helper

This repository provides some automation and other utilities to deploy OpenShift in a disconnected environment.

Currently supports the following patterns:

1. [**Downloading OpenShift releases to a local directory and package as a TAR file.**](#1-download-openshift-releases-and-operator-catalog-to-a-local-directory-and-package-as-a-tar-file) - This is intended to be done in a network with WAN access or a via a DMZ host.
2. **Extracting that TAR file to a directory, and pushing to a registry.** - Once the TAR has been transported from the DMZ to a disconnected/secure enclave, you would extract it and push to a local registry to be used for installation.
3. Setting up a local Docker Registry.
4. [**Setting up a local Harbor Registry.**](#4-setting-up-a-local-harbor-registry) - Deploy a quick Harbor registry for testing.

## 1. Download OpenShift Releases and Operator Catalog to a local directory and package as a TAR file

1. Modify the `inventory` file under the `dmzMirror` group to reflect the host that is running the mirroring process.  If you're running this via the CLI on the same node in the DMZ then just modify to run as a localhost entry.
2. Download a Red Hat Registry Pull Secret and save it to a file: https://cloud.redhat.com/openshift/install/pull-secret
   1. Optionally, if running via Tower or storing the Pull Secret as a Vaulted variable, you can define the Pull Secret in a variable called `rh_pull_secret` with the content wrapped in a single quote.
3. Configure any additional variables for what to mirror - by default it mirrors OpenShift 4.12.15 with a set of additional releases to upgrade to 4.13.10 with the shortest path.  A set of Operators are also set as defaults that should work for many bare metal deployments.

> You can specify Operators to mirror simply by their package name from the target Operator Catalog - unless specified, the automation will determine the default channel to mirror.

```bash=
# Run the automation
ansible-playbook -i inventory download-to-tar.yml
```

## 4. Setting up a local Harbor Registry

In the case you need a Harbor registry to work against, you can quickly spin one up on any subscribed RHEL system - probably also works with CentOS/Rocky/etc, just haven't tested it.

The automation handles package installation, firewall configuration, downloading/configuring/installing Docker and Harbor.

**All that you need to bring is an SSL certificate** - see the instructions below under [**SSL Certificate Generation**](#ssl-certificate-generation) for a quick way to do so in case you don't have an established SSL CA to generate certificates from.

If the system the Harbor registry is on is accessible from the public Internet then you could use something like Let's Encrypt.

1. Modify the `inventory` file under the `harbor` group to reflect the target host that will run Harbor.  If you're running this on the same target host then just modify to a localhost type inventory host with `ansible_connection=local ansible_host=localhost`.
2. Alter the variable to match your Harbor hostname, admin password, and SSL Certificate information.
3. If your Harbor system is behind an outbound proxy then just enable the `proxy` variables in the Playbook.

```bash=
# Run the automation playbook
ansible-playbook -i inventory
```

### Post Configuration for Harbor Mirroring

To import the OpenShift Releases and Operator Catalog into a Harbor Registry, you'll need to do a few things:

1. Create a new **Project** like `oc-mirror` - make sure it's publicly accessible.
2. Create a **Robot Account** so you don't need to log in as a user - or log in as a user, doesn't matter.  Make sure the Robot Account has access to the Project.

## Helpful Commands

### List Operators in an Operator Catalog

```bash=
# List all the available Operator Catalogs for a specific OpenShift release
oc mirror list operators --version=4.13

# List the Operators in the Operator Indexes
oc mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.13
oc mirror list operators --catalog=registry.redhat.io/redhat/certified-operator-index:v4.13
oc mirror list operators --catalog=registry.redhat.io/redhat/community-operator-index:v4.13
oc mirror list operators --catalog=registry.redhat.io/redhat/redhat-marketplace-index:v4.13

# List all channels in an operator package
oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.13 --package=cincinnati-operator
```

### SSL Certificate Generation

Here is an example of how to create a simple CA and Server SSL certificate:

```bash=
# Create the CA key
openssl genrsa -out ca.key 4096

# Generate a self-signed CA certificate
openssl req -x509 -new -nodes -sha512 -days 3650 \
 -subj "/C=US/ST=Tennessee/L=Nashville/O=ContainersRUs/OU=InfoSec/CN=RootCA" \
 -key ca.key \
 -out ca.crt

# Add the Root CA to your system trust
cp ca.crt /etc/pki/ca-trust/source/anchors/harbor-ca.pem
update-ca-trust

# You'll also need to add that CA Cert to whatever system you're accessing Harbor with

# Generate a Server Certificate Key
openssl genrsa -out harbor.example.com.key 4096

# Generate a Server Certificate Signing Request
openssl req -sha512 -new \
    -subj "/C=US/ST=Tennessee/L=Nashville/O=ContainersRUs/OU=DevOps/CN=harbor.example.com" \
    -key harbor.example.com.key \
    -out harbor.example.com.csr

# Create an x509 v3 Extension file
cat > openssl-v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=harbor.example.com
DNS.2=harbor
EOF

# Sign the Server Certificate with the CA Certificate
openssl x509 -req -sha512 -days 730 \
    -extfile v3.ext \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -in harbor.example.com.csr \
    -out harbor.example.com.crt

# Bundle the Server Certificate and the CA Certificate
cat harbor.example.com.crt ca.crt > harbor.example.com.bundle.crt
```

If using this process for a Harbor Registry then provide the `harbor.example.com.bundle.crt` file as the `ssl_certificate` in the Ansible Playbook and the `harbor.example.com.key` as the `ssl_certificate_key` variable.
