.. contents:: **Contents**

build-mc
============

Builds optimized version of `Midnight Commander <https://github.com/MidnightCommander/mc>`_ including patches into custom location on Debian flavoured systems.

Supports:

- multiple release versions
- git version (by specifying branch or commit)
- building per user or system wide


Compilation
-----------

Installing build dependencies
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

First, you need to install a few **required** packages — **and no, this is not optional in any way**. They require about ``280 MB`` disk space. These steps must be performed by the ``root`` user (i.e. in a root shell, or by writing ``sudo`` before the actual command):

.. code-block:: shell

   apt-get update
   apt-get install sudo coreutils binutils build-essential git time \
       autopoint autoconf automake libtool pkg-config unzip curl locales \
       e2fslibs-dev gettext libaspell-dev libglib2.0-dev libgpm-dev \
       libslang2-dev libssh2-1-dev libx11-dev


Getting repo
^^^^^^^^^^^^

.. code-block:: shell

   mkdir -p ~/src/; cd ~/src/
   git clone https://github.com/chros73/build-mc.git
   cd build-mc


Compiling
^^^^^^^^^

You can compile it for a regular user:

.. code-block:: shell

   time nice -n 19 ./build.sh mc


or system wide (needs root shell, or by writing ``sudo`` before the actual command):

.. code-block:: shell

   time nice -n 19 ./build.sh install


You can compile the specified ``git`` version by adding a ``git`` second argument to the above commands.

If you want to turn off optimization for some reason (e.g. moving the build to a different box) it can be done by adding ``optimize_build=no`` in front of the above commands, e.g.:

.. code-block:: shell

   optimize_build=no time nice -n 19 ./build.sh mc git


Change log
----------

See `CHANGELOG.md <CHANGELOG.md>`_ for more details.
