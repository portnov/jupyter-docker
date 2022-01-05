FROM debian:unstable
MAINTAINER Ilya Portnov <portnov@iportnov.ru>

RUN echo deb http://mirror.yandex.ru/debian/ unstable main non-free contrib >> /etc/apt/sources.list

RUN apt-get update

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y \
	build-essential \
	ca-certificates \
	curl wget \
	git subversion \
	libcurl4-openssl-dev \
	libffi-dev \
	libsqlite3-dev \
	libzmq3-dev \
	pandoc \
	python3 \
	python3-dev \
  python3-pip \
	sqlite3 \
	zlib1g-dev \
  python-setuptools python3-setuptools \
  sbcl autoconf libgmp-dev \
  ghc cabal-install alex happy cpphs pkg-config \
  cl-quicklisp \
  r-recommended r-cran-ggplot2 libssh2-1-dev libssl-dev \
  julia

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	texlive-fonts-recommended \
	texlive-latex-base \
	texlive-latex-extra \
  octave gnuplot-nox \
  libgtk2.0-dev

RUN pip3 --no-cache-dir install ipykernel && \
  python3 -m ipykernel.kernelspec && \
  pip3 install notebook && \
  pip3 install jupyterlab && \
  pip3 install ipywidgets && \
  pip3 install --no-cache-dir widgetsnbextension && \
  pip3 install --no-cache-dir scipy matplotlib && \
  pip3 install octave_kernel

# Install Tini
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini.asc /tini.asc
RUN gpg --batch --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
 && gpg --batch --verify /tini.asc /tini \
 && chmod +x /tini

# Default notebook profile.
RUN mkdir -p -m 700 /root/.jupyter/ && \
    echo "c.NotebookApp.ip = '*'" >> /root/.jupyter/jupyter_notebook_config.py

# Download & build sbcl
ENV SBCL_VERSION 2.1.11
RUN cd /usr/src/ && \
  wget http://prdownloads.sourceforge.net/sbcl/sbcl-${SBCL_VERSION}-source.tar.bz2?download && \
  tar xf sbcl-${SBCL_VERSION}-source.tar.bz2\?download && \
  cd sbcl-${SBCL_VERSION} && \
  bash make.sh && \
  bash install.sh

# download & build fricas
RUN cd /usr/src/ && \
  git clone https://github.com/fricas/fricas.git && \
  cd fricas/ && \
  ./build-setup.sh && \
  ./configure --enable-gmp && \
  make -j4 && \
  make install

ENV SBCL_HOME /usr/local/lib/sbcl

RUN apt-get install -y cl-asdf cl-hunchentoot && \
 	pip3 install jfricas

# install maxima
RUN cd /usr/src/ && \
  wget 'https://jztkft.dl.sourceforge.net/project/maxima/Maxima-source/5.45.1-source/maxima-5.45.1.tar.gz' -O maxima.tar.gz && \
  tar xf maxima.tar.gz && \
  cd maxima-5.45.1/ && \
  ./configure && \
  make -j4 && \
  make install

WORKDIR /usr/src/

# # install ihaskell
RUN cabal update && \
  cabal install cryptonite ihaskell --reorder-goals --ghc-options=-opta-Wa,-mrelax-relocations=no
RUN cp ~/.cabal/bin/ihaskell /usr/local/bin/ && \
  /usr/local/bin/ihaskell install
# 
# # install ihaskell-diagrams
RUN cabal install --ghc-options=-opta-Wa,-mrelax-relocations=no gtk2hs-buildtools && \
  cp ~/.cabal/bin/gtk* /usr/local/bin/ && \
  cabal install --ghc-options=-opta-Wa,-mrelax-relocations=no diagrams diagrams-cairo && \
  cabal install --ghc-options=-opta-Wa,-mrelax-relocations=no ihaskell-diagrams

RUN git clone https://github.com/robert-dodier/maxima-jupyter && \
	cd maxima-jupyter/ && \
	echo ":lisp (require \"asdf\")\n:lisp (load \"/usr/share/common-lisp/source/quicklisp/quicklisp.lisp\")\n:lisp (quicklisp-quickstart:install)\n:lisp (load \"load-maxima-jupyter.lisp\")\njupyter_install_image();\n" > install.maxima && \
	maxima -b install.maxima

# install R for jupyter (IRkernel)
RUN /bin/echo -e "install.packages(c('repr', 'pbdZMQ', 'devtools'), repos='http://cran.us.r-project.org')\n\
  devtools::install_github('IRkernel/IRdisplay')\n\
  devtools::install_github('IRkernel/IRkernel')\n\
  IRkernel::installspec()\n" > install.R && \
  R -f install.R

# install Julia for jupyter
# RUN julia -e 'Pkg.add("IJulia")' && \
#   julia -e 'Pkg.add("PyPlot")' && \
#   julia -e 'Pkg.add("DataFrames")'

RUN apt-get install -y nodejs npm

VOLUME /notebooks
VOLUME /root/.jupyter
WORKDIR /notebooks

EXPOSE 8888

ENTRYPOINT ["/tini", "--"]
CMD ["jupyter", "lab", "--no-browser", "--allow-root"]
