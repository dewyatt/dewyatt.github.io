---
layout: post
title: Continuous Deployment of Pastely with GKE/Kubernetes, Ansible, and Jenkins
date: 2016-07-04 04:05:12 -0400
---

Introduction
============

[Pastely](http://github.com/dewyatt/pastely-backend) is a little web app for sharing code pastes, a la pastebin and many others.
**Note**: Limited browser support due to the use of CSS flexbox. Modern Chrome/Firefox should work.
It was written for the simple purpose of learning a handful of new technologies.

It is hosted in Google's Container Engine/Kubernetes and automatically deployed with Docker, Ansible, and Jenkins.

![](/assets/images/26.png)

The deployment scenario described here is not ideal but it's a good start. Generally I believe it's better to have separate staging and production clusters if possible, rather than using namespaces as below.

Technologies Overview
=====================

Common Technologies
-------------------

The frontend and backend both utilize some common technologies, including:

-   [Docker](https://www.docker.com)
-   [Ansible](https://www.ansible.com)
-   [Kubernetes](http://kubernetes.io)
-   [Alpine Linux](http://alpinelinux.org)
-   [Jenkins](https://jenkins.io/)

Backend
-------

The backend portion provides a simple API of HTTP endpoints to store and retrieve pastes.

### Languages

-   Python 3

### Libraries/Frameworks

-   [Django](https://www.djangoproject.com)
-   [Django Rest Framework](http://www.django-rest-framework.org)

### Tooling / Software

-   [pip](https://pypi.python.org/pypi/pip) + [virtualenv](https://virtualenv.pypa.io)
-   [uWSGI](http://projects.unbit.it/uwsgi)

Frontend
--------

The frontend is a plain React web app.

It does not use Redux/Flux. I did an initial implementation using Alt.js but decided to keep things simple and removed it.

### Languages

-   Javascript
-   ES6
-   JSX

### Libraries/Frameworks

-   [React](reactjs.com)
-   [React Router](https://github.com/reactjs/react-router)
-   [MUI](https://www.muicss.com/)

### Tooling / Software

-   [Webpack](https://webpack.github.io)
-   [NPM](http://npmjs.com)
-   [Babel](https://babeljs.io)
-   [Nginx](https://www.nginx.com)

Running Locally
===============

Running the app locally is simple.

Frontend
--------

```bash
git clone https://github.com/dewyatt/pastely-frontend.git
cd pastely-frontend
npm install
npm start
```

Backend
-------

```bash
git clone https://github.com/dewyatt/pastely-backend.git
cd pastely-backend
virtualenv3 venv
. venv/bin/activate
pip install -r requirements/local.txt
python manage.py makemigrations --settings=pastely.settings.local
python manage.py makemigrations --settings=pastely.settings.local paste
python manage.py migrate --settings=pastely.settings.local
python manage.py runserver 127.0.0.1:8000 --settings=pastely.settings.local
```

Connect
-------

Now you can connect to [http://127.0.0.1:8080](http://127.0.0.1:8080). The Django admin interface is available at `/admin`. You can create a user to access the admin interface like so:

```bash
python manage.py createsuperuser --settings=pastely.settings.local
```

Bootstrapping in GKE / Kubernetes
=================================

Getting things going within GKE is a bit more involved.

To start with, you must install the [Google Cloud SDK](https://cloud.google.com/sdk).

Then, you'll want to [create a new project](https://console.cloud.google.com/iam-admin/projects) in the Google Cloud Platform console. This gives you a project ID that you can substitute below (mine was `pastely-1357`).

Create a Cluster
----------------

```bash
# initialize the Google Cloud SDK, authenticate, set default project, zone, etc.
gcloud init
# create a k8s cluster using the defaults
gcloud container clusters create pastely
# set up credentials for k8s
gcloud container clusters get-credentials pastely
# check: make sure the cluster is visible
kubectl cluster-info
```

Now that we have a cluster running, we can create a couple of k8s namespaces to hold our staging and production resources.

This makes it easier to keep things separated without creating multiple clusters.

You can create namespaces directly with `kubectl create namespace` or you can use YAML/JSON:

```bash
cd pastely-backend/deploy
# create k8s namespaces to hold staging+production resources
kubectl create -f kubernetes/namespaces.yaml
```

Deploy the Backend
------------------

### PostgreSQL Database

Now we can deploy our database.

First, we'll need to create a k8s secret that contains information like the database username/password.

We'll pass this secret information via the environment to the [official PostgreSQL docker container](https://hub.docker.com/_/postgres).

The file `pastely-backend/deploy/kubernetes/secrets/staging/staging-database-secret.yaml` contains base64-encoded data similar to the below.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pastely-database-secret
type: Opaque
data:
  user: dXNlcm5hbWU=
  password: eW91cnBhc3N3b3Jk
  database: ZGF0YWJhc2VuYW1l
```

With it, we can create our database secret:

```bash
# create our database secret
kubectl create -f kubernetes/secrets/staging/staging-database-secret.yaml --namespace=pastely-staging
```

Then we can move on to creating the database deployment.

```bash
# create a persistent disk for the postgresql database in the staging environment
gcloud compute disks create pastely-pg-data-staging --size 200GB
# create a deployment for the database
kubectl create -f kubernetes/deployments/database.yaml --namespace=pastely-staging
# create a service to refer to the database via DNS
kubectl create -f kubernetes/services/database.yaml --namespace=pastely-staging
```

### Backend

First we need to build a container.

```bash
docker build \
--build-arg=deploy_environment=staging \
--build-arg=git_sha1=f87865de08c452475bd419cfb90b4b8d77bb1b99 \
-t gcr.io/pastely-1357/pastely-backend:f87865de08c452475bd419cfb90b4b8d77bb1b99.staging.v1 .
```

This would build a docker container based on the git commit referenced. The arguments are passed into the Dockerfile and then to Ansible to build out the container.

Once built, it can be uploaded with:

```bash
gcloud docker push gcr.io/pastely-1357/pastely-backend:f87865de08c452475bd419cfb90b4b8d77bb1b99.staging.v1
```

This would upload it to the [Google Container Registry](https://console.cloud.google.com/kubernetes/images/list).

Now again we will want to create a secret. This time the secret is an INI file used by the Django app to retrieve the database credentials and Django secret key. It looks something like this:

```ini
[pastely]
SECRET_KEY=djangosecretkeyhere
DATABASE_NAME=databasename
DATABASE_USER=username
DATABASE_PASSWORD=yourpassword
DATABASE_HOST=pastely-database
DATABASE_PORT=5432
```

We can turn this into a k8s secret with:

```bash
# create a secret from our config.ini
kubectl create secret generic pastely-config-secret --from-file=config.ini=kubernetes/secrets/staging/config.ini --namespace=pastely-staging
```

Now the first time we deploy the backend, we will want to disable the livenessProbe and readinessProbe. The reason is that they use data that is not yet in the database, so these checks will fail.

One way to do this is to simply comment out the livenessProbe and readinessProbe sections of the file `kubernetes/deployments/backend.yaml` file and then create the backend deployment:

```bash
# create the backend deployment
kubectl create -f kubernetes/deployments/backend.yaml --namespace=pastely-staging
```

Then we can execute an interactive shell on one of the backend containers. This gives us an opportunity to perform database migrations, load fixtures, create a user, etc.

```bash
kubectl get pods --namespace=pastely-staging
NAME                                READY     STATUS    RESTARTS   AGE
pastely-backend-3062118379-4m774    1/1       Running   0          10h
pastely-backend-3062118379-kej89    1/1       Running   0          10h
pastely-database-1888716277-6nuhm   1/1       Running   0          17h
pastely-frontend-715571195-onwt9    1/1       Running   0          10h
pastely-frontend-715571195-tuilp    1/1       Running   0          10h
```

```bash
kubectl exec -ti pastely-backend-3062118379-4m774 /bin/sh --namespace=pastely-staging
. venv/bin/activate
python manage.py makemigrations --settings=pastely.settings.staging
python manage.py makemigrations --settings=pastely.settings.staging paste
python manage.py migrate --settings=pastely.settings.staging
python manage.py loaddata health_check --settings=pastely.settings.staging
python manage.py createsuperuser --settings=pastely.settings.staging
```

Now we can uncomment the livenessProbe and readinessProbe in `kubernetes/deployments/backend.yaml` and modify the deployment.

```bash
# restore the livenessProbe and readinessProbe after uncommenting them
kubectl apply -f kubernetes/deployments/backend.yaml --namespace=pastely-staging
```

Finally, we can create the service for the backend.

```bash
# create the backend service so we can resolve the name 'pastely-backend' with DNS
kubectl create -f kubernetes/services/backend.yaml --namespace=pastely-staging
```

Deploy the Frontend
-------------------

### Build the Container

Just like before, we need to build a container for the frontend.

```bash
# build our container
docker build --build-arg=deploy_environment=staging --build-arg=server_name=pastely-staging.dewyatt.com --build-arg=git_sha1=49a42187c8a51eb980a98fac0ad2e633491ae586 -t gcr.io/pastely-1357/pastely-frontend:49a42187c8a51eb980a98fac0ad2e633491ae586.staging.v1 .
# push it out to the Google Container Repository
gcloud docker push gcr.io/pastely-1357/pastely-frontend:49a42187c8a51eb980a98fac0ad2e633491ae586.staging.v1
```

Then we can create the deployment and the service.

```bash
# create the deployment
kubectl create -f deploy/kubernetes/deployments/frontend.yaml --namespace=pastely-staging
# create the service
kubectl create -f deploy/kubernetes/services/frontend.yaml --namespace=pastely-staging
```

This time, the service type is LoadBalancer. This will create a public/external IP after a few minutes.

```bash
# check to see if the external IP is ready
kubectl get services --namespace=pastely-staging
NAME CLUSTER-IP EXTERNAL-IP PORT (S) AGE
pastely-backend 10.115.254.142 <none> 8000/TCP 18h
pastely-database 10.115.255.182 <none> 5432/TCP 18h
pastely-frontend 10.115.243.24 146.148.77.173 80/TCP 18h
```

Here we can see the frontend has an external IP address which can be accessed directly, entered into DNS, etc.

Continuous Deployment with Jenkins
==================================

Now that everything is bootstrapped (finally!), things are much simpler.

With newer versions of Jenkins, we can create a pipeline that will execute when a git repository is updated. You can store the pipeline script within the repository itself (a Jenkinsfile).

For example, for the backend:

```groovy
node {
    stage 'checkout'
    git 'https://github.com/dewyatt/pastely-backend.git'

    stage 'testing'
    sh './deploy/test.sh'

    stage 'build-staging'
    sh 'git rev-parse HEAD | head -c 40 > GIT_COMMIT'
    git_sha1=readFile('GIT_COMMIT')
    sh "./deploy/build.sh staging $git_sha1"

    stage 'deploy-staging'
    sh "./deploy/deploy.sh staging $git_sha1"

    deploy_prod=input message: 'Deployed to staging. Do you want to deploy to production?'
    stage 'build-production'
    sh "./deploy/build.sh production $git_sha1"

    stage 'deploy-production'
    sh "./deploy/deploy.sh production $git_sha1"
}
```

This simply uses a couple of scripts to automatically test, build, and deploy to the staging environment when a new commit is pushed. It then prompts for approval to deploy to the production environment.

The `build.sh` script builds a container just like we did above.

The `deploy.sh` script uploads it to GCR and uses `kubectl patch` to modify the deployment with the new image target.

Kubernetes takes care of the rest by building out new pods and terminating the old ones, all transparently without interrupting service.
