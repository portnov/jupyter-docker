FROM debian:jessie
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
	python \
	python3 \
	python-dev \
	python3-dev \
  python-pip \
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

RUN pip2 --no-cache-dir install ipykernel && \
  pip3 --no-cache-dir install ipykernel && \
  python2 -m ipykernel.kernelspec && \
  python3 -m ipykernel.kernelspec && \
  pip2 install notebook && \
  pip3 install notebook && \
  pip2 install ipywidgets && \
  pip3 install ipywidgets && \
  pip2 install --no-cache-dir widgetsnbextension && \
  pip3 install --no-cache-dir widgetsnbextension && \
  pip2 install --no-cache-dir scipy matplotlib && \
  pip3 install --no-cache-dir scipy matplotlib && \
  pip2 install octave_kernel && \
  pip3 install octave_kernel && \
  python2 -m octave_kernel.install && \
  python3 -m octave_kernel.install

# Install Tini
RUN curl -L https://github.com/krallin/tini/releases/download/v0.6.0/tini > tini && \
	echo "d5ed732199c36a1189320e6c4859f0169e950692f451c03e7854243b95f4234b *tini" | sha256sum -c - && \
	mv tini /usr/local/bin/tini && \
	chmod +x /usr/local/bin/tini

# Default notebook profile.
RUN mkdir -p -m 700 /root/.jupyter/ && \
    echo "c.NotebookApp.ip = '*'" >> /root/.jupyter/jupyter_notebook_config.py

# Download & build sbcl 1.3.6
RUN cd /usr/src/ && \
  wget http://prdownloads.sourceforge.net/sbcl/sbcl-1.3.6-source.tar.bz2?download && \
  tar xf sbcl-1.3.6-source.tar.bz2\?download && \
  cd sbcl-1.3.6 && \
  bash make.sh && \
  bash install.sh

# download & build fricas
RUN cd /usr/src/ && \
  svn checkout svn://svn.code.sf.net/p/fricas/code/trunk fricas && \
  cd fricas/ && \
  ./build-setup.sh && \
  ./configure --enable-gmp && \
  make -j4 && \
  make install

ENV SBCL_HOME /usr/local/lib/sbcl

# download & build fricas_jupyter
RUN cd /usr/src/ && \
  git clone https://github.com/nilqed/fricas_jupyter.git && \
  cd fricas_jupyter && \
  ./install.sh

# install ihaskell
RUN cabal update && \
  cabal install cryptonite ihaskell --reorder-goals --ghc-options=-opta-Wa,-mrelax-relocations=no && \
  ln ~/.cabal/bin/ihaskell /usr/local/bin/ && \
  ihaskell install

# install ihaskell-diagrams
RUN cabal install --ghc-options=-opta-Wa,-mrelax-relocations=no gtk2hs-buildtools && \
  ln ~/.cabal/bin/gtk* /usr/local/bin/ && \
  cabal install --ghc-options=-opta-Wa,-mrelax-relocations=no diagrams diagrams-cairo && \
  cabal install --ghc-options=-opta-Wa,-mrelax-relocations=no ihaskell-diagrams

# install maxima
RUN cd /usr/src/ && \
  wget 'http://downloads.sourceforge.net/project/maxima/Maxima-source/5.38.1-source/maxima-5.38.1.tar.gz?r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Fmaxima%2Ffiles%2FMaxima-source%2F5.38.1-source%2F&ts=1466440822&use_mirror=heanet' -O maxima.tar.gz && \
  tar xf maxima.tar.gz && \
  cd maxima-5.38.1/ && \
  ./configure && \
  make -j4 && \
  make install

WORKDIR /usr/src/

RUN /bin/echo -e '(load #p"/usr/share/cl-quicklisp/quicklisp.lisp")\n\
  (quicklisp-quickstart:install)' > install-quicklisp.lisp && \
  sbcl --script install-quicklisp.lisp && \
  git clone https://github.com/robert-dodier/maxima-jupyter && \
  cd maxima-jupyter && \
  /bin/echo -e "parse_string(\"1\");\n\
:lisp (load \"/usr/local/lib/sbcl/contrib/sb-rotate-byte.fasl\")\n\
:lisp (load \"/root/quicklisp/setup.lisp\")\n\
:lisp (loop for system in (list :uiop  :asdf :sb-posix) do (asdf:operate 'asdf:load-op system))\n\
:lisp (load \"/usr/src/maxima-jupyter/load-maxima-jupyter.lisp\")\n\
:lisp (sb-ext:save-lisp-and-die \"maxima-jupyter.core\" :toplevel 'cl-jupyter:kernel-start :executable t)\n\
quit();\n" > build-core.maxima && \
  cat build-core.maxima && \
  maxima -b=build-core.maxima && \
  python3 install-maxima-jupyter.py --maxima-jupyter-exec=$(pwd)/maxima-jupyter.core

# install R for jupyter (IRkernel)
RUN /bin/echo -e "install.packages(c('repr', 'pbdZMQ', 'devtools'), repos='http://cran.us.r-project.org')\n\
  devtools::install_github('IRkernel/IRdisplay')\n\
  devtools::install_github('IRkernel/IRkernel')\n\
  IRkernel::installspec()\n" > install.R && \
  R -f install.R

# install Julia for jupyter
RUN julia -e 'Pkg.add("IJulia")' && \
  julia -e 'Pkg.add("PyPlot")' && \
  julia -e 'Pkg.add("DataFrames")'

VOLUME /notebooks
VOLUME /root/.jupyter
WORKDIR /notebooks

EXPOSE 8888

ENTRYPOINT ["tini", "--"]
CMD ["jupyter", "notebook", "--no-browser"]
