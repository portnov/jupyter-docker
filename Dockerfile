FROM ubuntu:24.04
MAINTAINER Ilya Portnov <portnov@bk.ru>

ENV TINI_VERSION v0.19.0
ENV SBCL_VERSION 2.5.0
ENV MAXIMA_VERSION 5.47.0
ENV JULIA_MAJOR_VERSION 1.11
ENV JULIA_VERSION 1.11.2

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
  python3-setuptools \
  sbcl autoconf libgmp-dev \
  ghc cabal-install alex happy cpphs pkg-config \
  cl-quicklisp \
  r-recommended r-cran-ggplot2 libssh2-1-dev libssl-dev

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	texlive-fonts-recommended \
	texlive-latex-base \
	texlive-latex-extra \
  octave gnuplot-nox \
  libgtk2.0-dev

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-venv

RUN python3 -m venv /python && \
  /python/bin/pip3 install ipykernel && \
  /python/bin/python3 -m ipykernel.kernelspec && \
  /python/bin/pip3 install notebook && \
  /python/bin/pip3 install jupyterlab && \
  /python/bin/pip3 install ipywidgets && \
  /python/bin/pip3 install --no-cache-dir widgetsnbextension && \
  /python/bin/pip3 install --no-cache-dir scipy matplotlib && \
  /python/bin/pip3 install octave_kernel

# Install Tini
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini.asc /tini.asc
RUN gpg --batch --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
 && gpg --batch --verify /tini.asc /tini \
 && chmod +x /tini

# Default notebook profile.
RUN mkdir -p -m 700 /root/.jupyter/ && \
    echo "c.NotebookApp.ip = '*'" >> /root/.jupyter/jupyter_notebook_config.py

# Download & build sbcl
RUN cd /usr/src/ && \
  wget http://prdownloads.sourceforge.net/sbcl/sbcl-${SBCL_VERSION}-source.tar.bz2?download && \
  tar xf sbcl-${SBCL_VERSION}-source.tar.bz2\?download && \
  rm sbcl-${SBCL_VERSION}-source.tar.bz2\?download && \
  cd sbcl-${SBCL_VERSION} && \
  bash make.sh && \
  bash install.sh

ENV SBCL_HOME /usr/local/lib/sbcl

RUN apt-get install -y cl-asdf

ADD hsbcl.lisp /usr/src/hsbcl.lisp

RUN sbcl --eval '(load "/usr/src/hsbcl.lisp")' --quit

# download & build fricas
RUN cd /usr/src/ && \
  git clone https://github.com/fricas/fricas.git && \
  cd fricas/ && \
  ./build-setup.sh && \
  ./configure --with-lisp=/usr/local/bin/hsbcl --enable-gmp && \
  make -j4 && \
  make install

ENV PATH="/python/bin:$PATH"

RUN . /python/bin/activate && \
 	/python/bin/pip3 install wheel && \
 	/python/bin/pip3 install jupyter && \
 	/python/bin/pip3 install requests && \
  /python/bin/pip3 install jfricas

# install maxima
RUN cd /usr/src/ && \
  wget "https://altushost-swe.dl.sourceforge.net/project/maxima/Maxima-source/${MAXIMA_VERSION}-source/maxima-${MAXIMA_VERSION}.tar.gz?viasf=1" -O maxima.tar.gz && \
  tar xf maxima.tar.gz && \
  rm maxima.tar.gz && \
  cd maxima-${MAXIMA_VERSION}/ && \
  ./configure && \
  make -j4 && \
  make install

WORKDIR /usr/src/

# install ihaskell
RUN cabal update && \
  cabal install cryptonite ihaskell --reorder-goals --ghc-options=-opta-Wa,-mrelax-relocations=no
RUN cp ~/.cabal/bin/ihaskell /usr/local/bin/ && \
  /usr/local/bin/ihaskell install
# 
# install ihaskell-diagrams
RUN cabal install --ghc-options=-opta-Wa,-mrelax-relocations=no gtk2hs-buildtools && \
  cp ~/.cabal/bin/gtk* /usr/local/bin/ && \
  cabal install --ghc-options=-opta-Wa,-mrelax-relocations=no diagrams diagrams-cairo && \
  cabal install --ghc-options=-opta-Wa,-mrelax-relocations=no ihaskell-diagrams

ADD install.maxima /usr/src

RUN git clone https://github.com/robert-dodier/maxima-jupyter && \
	cd maxima-jupyter/ && \
  maxima -b /usr/src/install.maxima

# install R for jupyter (IRkernel)
RUN /bin/echo -e "install.packages(c('repr', 'pbdZMQ', 'devtools'), repos='http://cran.us.r-project.org')\n\
  devtools::install_github('IRkernel/IRdisplay')\n\
  devtools::install_github('IRkernel/IRkernel')\n\
  IRkernel::installspec()\n" > install.R && \
  R -f install.R

# install Julia
RUN cd /opt && \
  wget https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MAJOR_VERSION}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz -O julia.tar.gz && \
  tar xf julia.tar.gz && \
  ln -s /opt/julia-${JULIA_VERSION}/bin/julia /usr/local/bin && \
  rm julia.tar.gz

# install Julia for jupyter
RUN julia -e 'using Pkg; Pkg.add("IJulia")' && \
  julia -e 'using Pkg; Pkg.add("PyPlot")' && \
  julia -e 'using Pkg; Pkg.add("DataFrames")'

#RUN apt-get install -y nodejs npm
RUN wget -q -O- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash && \
  . ~/.bashrc && \
  nvm install node
RUN /python/bin/pip3 install jupyterlab-theme-solarized-dark jupyterlab-gruvbox-dark

VOLUME /notebooks
VOLUME /root/.jupyter
WORKDIR /notebooks

EXPOSE 8888

ENTRYPOINT ["/tini", "--"]
CMD ["jupyter", "lab", "--no-browser", "--allow-root"]
