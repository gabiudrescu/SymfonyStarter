How to use Monofony with Docker
===============================

Docker eliminates the „works on my computer” issue by allowing you to run an application on the same environment configuration
on development, testing and production. You don't have to worry anymore if the PHP version is correct or if the MySQL
configuration won't put you in any trouble.

Monofony is using a forked version of `SyliusStandard <https://github.com/Sylius/Sylius-Standard>`_ docker configuration.
The differences are:

- the php and node containers do not run as root, to avoid messing up permissions on the host

- this fork uses a scratch container to hold the same context throughout the multistage build


System requirements
-------------------

In order to get everything up and running, you should have installed on your system the following versions of Docker and
Docker Compose:

.. code-block:: bash

    $ docker -v
    Docker version 18.06.1-ce, build e68fc7a

    $ docker-compose -v
    docker-compose version 1.24.0, build 0aa59064

Start working with Docker and Monofony
--------------------------------------

Next step is to clone the git repository on your local machine and then run the following commands:

.. code-block:: bash

    $ docker-compose pull

This will pull from the registry all required containers for you, so you can avoid building them locally and waste time
on that.

Before actually bring the entire stack up, you should check your user and group id:

.. code-block:: bash

    $ id

    uid=1000(my_user) gid=1000(my_user) groups=1000(my_user),4(adm),27(sudo),998(docker)

The output of this command let's you see the current user id and groups that is member of. If your user id is different,
you should change it in ``docker-compose.yml`` - change the argument ``USER_UID``

If your user is not member of the docker group, you must run the commands with sudo in order to avoid errors.

Now it's time to bring everything to life:

.. code-block:: bash

    $ docker-compose up

This will open all the containers defined in ``docker-compose.yml`` in the root folder of the cloned git repository. The
default file makes a few assumptions:

 - you are running a development environment
 - you want certain ports to be exposed and available from your host (e.g. MySQL database)
 - you want your application to actually send emails, through Mailhog, a SMTP fake server
 - you want to keep a terminal with all the log output from the containers to make sure you spot errors if they happen
 - it mounts ``~/.ssh`` and ``~/.composer`` to your containers to make your private ssh keys available,
   in case you need to connect to any private repository and composer cached dependencies.

If you want to start everything in background, you should run the command below:

.. code-block:: bash

    $ docker-compose up -d

Customization
-------------

You can customize the docker by either modifying the ``docker-compose.yml`` file or by providing an override file.

Create a file with the name ``docker-compose.override.yml`` in the root of your project and include the followings:

.. code-block:: yaml

    version: '3.4'

    services:
        php:
            build:
                args:
                    - USER_ID=2000

        nodejs:
            build:
                args:
                    - USER_ID=2000

This will allow you to run the php and node containers with another user ID than the default one - 1000. Anything you write
in the override file differently than in the original file will supersede the later one.

Your docker setup can also be influenced by setting some arguments or environments to different values:

.. csv-table:: Arguments
    :header: Value,Notes

    "ARG PHP_VERSION=7.3"
    "ARG NODE_VERSION=10"
    "ARG NGINX_VERSION=1.16"
    "ARG APCU_VERSION=5.1.17"
    "ARG USER_UID=1000"
    "ARG APP_ENV=prod"

All these arguments are taken into consideration on container build time. Any change to these variables will determine
Docker to rebuild the stack.

PHP and Nginx configuration can be updated by editing the files from ``docker/php/`` or ``docker/nginx``. The ini files
contain the configuration for extensions, vhosts and everything you might need.

Deploy the production environment
---------------------------------

This container system is almost ready for production environment as well. Once you have the images built locally or in CI,
you can push them to your own registry and deploy it from there.

Get inspired on how to do this by observing the ``docker-compose.prod.yml`` file from `SyliusStandard <https://github.com/Sylius/Sylius-Standard>`_

Using Gitlab for private docker registry
----------------------------------------

GitLab is offering unlimited private docker repository hosting. This means that if you want to avoid the hassles of building
your own registry infrastructure of if you want to test a private setup without committing to paid services, you should switch
to Gitlab to host your files and build your images with Gitlab CI.

Below you can find a sample of GitLab CI configuration used to build Monofony docker containers and push them to a private
docker repository.

.. code-block:: yaml

    stages:
        - build

    docker:
        stage: build
        image: qmarketing/dind-docker-compose:18.09.5
        variables:
            DOCKER_HOST: tcp://docker:2375/
            DOCKER_DRIVER: overlay2
        services:
            - docker:dind
        before_script:
            - docker info
            - docker login -u gitlab-ci-token -p $CI_JOB_TOKEN registry.gitlab.com
            - docker-compose pull
        script:
            - docker-compose build
            - docker-compose push

Gitlab CI is using docker to run the tests and you need to specify a docker in docker setup in order to get things going.
Because by default, the standard docker image is not providing ``docker-compose``, this image will use a community provided
docker image. Read more `here <https://gitlab.com/gitlab-org/gitlab-foss/issues/30426>`_.

Your contribution
-----------------

This docker setup is far from perfect. It merely takes the work of the Sylius community and adds a little bit of improvement
to it. If you run Monofony and/or Sylius in production or if you use Docker to run the automated testing suite, feel free
to open a PR and contribute to this setup.

This documentation currently lacks guidance on how to setup:

 - the docker environment with Symfony binary instead of NGINX
 - how to do an actual deploy of the application with Docker (Swarm or Kubernetes)
 - how to setup SSL certificates for local and production environment
 - how to run this stack on Windows or MacOS and how to overcome platform specific issues
