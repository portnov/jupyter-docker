Jupyter-Docker README
=====================

This repo contains a simple Dockerfile for a container, which contains Jupyter
instance with the following set of kernels:

* Python3
* FriCAS
* Maxima
* iHaskell
* GNU R
* GNU Octave
* Julia

This container is supposed to be used locally only - it does not contain secure
enough configuration for use on public webservers.

Building
--------

    $ ./generate_jupyter_image.py -b

See also `./generate_jupyter_image.py --help` for additional options.

Running
-------

    $ docker run --name jupyter -p 8888:8888 jupyter

