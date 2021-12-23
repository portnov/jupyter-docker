Jupyter-Docker README
=====================

This repo contains a simple Dockerfile for a container, which contains Jupyter
instance with the following set of kernels:

* Python3
* FriCAS
* Maxima
* iHaskell
* GNU R

This container is supposed to be used locally only - it does not contain secure
enough configuration for use on public webservers.

Building
--------

    $ docker build -t jupyter .

Running
-------

    $ docker run --name jupyter -p 8888:8888 jupyter

