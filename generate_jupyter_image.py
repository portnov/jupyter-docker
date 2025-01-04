#!/usr/bin/python3

import argparse
import subprocess
from os.path import dirname, basename

GENERIC_INSTALL = r"""

RUN python3 -m venv /python && \
  /python/bin/pip3 install notebook && \
  /python/bin/pip3 install jupyterlab

ENV PATH="/python/bin:$PATH"

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

WORKDIR /usr/src/
"""

HEADER_TEMPLATE = r"""
FROM ubuntu:{ubuntu_version}
MAINTAINER Ilya Portnov <portnov@bk.ru>

RUN apt-get update

"""

TRAILER = r"""
RUN /python/bin/pip3 install jupyterlab-theme-solarized-dark jupyterlab-gruvbox-dark

VOLUME /notebooks
VOLUME /root/.jupyter
WORKDIR /notebooks

EXPOSE 8888

ENTRYPOINT ["/tini", "--"]
CMD ["jupyter", "lab", "--no-browser", "--allow-root"]
"""

GENERIC_DEPS = {
        'build-essential',
        'ca-certificates',
        'curl', 'wget',
        'git', 'gnupg',
        'libcurl4-openssl-dev',
        'libffi-dev',
        'libsqlite3-dev',
        'libzmq3-dev',
        'python3',
        'python3-venv',
        'python3-dev',
        'python3-pip',
        'python3-setuptools',
        'zlib1g-dev',
        'autoconf', 'libgmp-dev',
        'pkg-config',
        'libssh2-1-dev', 'libssl-dev'
    }

LISP_DEPS = {
        'sbcl', 'cl-quicklisp', 'cl-asdf'
    }

INSTALL_LISP = r"""
ENV SBCL_VERSION 2.5.0

# Download & build sbcl
RUN cd /usr/src/ && \
  wget http://prdownloads.sourceforge.net/sbcl/sbcl-${SBCL_VERSION}-source.tar.bz2?download -O sbcl.tar.bz2 && \
  tar xf sbcl.tar.bz2 && \
  rm sbcl.tar.bz2 && \
  cd sbcl-${SBCL_VERSION} && \
  bash make.sh && \
  bash install.sh

ENV SBCL_HOME /usr/local/lib/sbcl
"""

class Kernel:
    def __init__(self):
        pass

    def get_environment(self):
        return dict()

    def get_dependencies(self):
        return {}

    def specific_install(self):
        return "RUN /python/bin/pip3 install octave_kernel\n"

    def need_lisp(self):
        return False

class Python(Kernel):
    def specific_install(self):
        return r"""RUN /python/bin/pip3 install ipykernel && \
  /python/bin/python3 -m ipykernel.kernelspec && \
  /python/bin/pip3 install ipywidgets && \
  /python/bin/pip3 install --no-cache-dir widgetsnbextension && \
  /python/bin/pip3 install --no-cache-dir scipy matplotlib
"""

class Octave(Kernel):
    def get_dependencies(self):
        return {'octave', 'gnuplot-nox'}

    def specific_install(self):
        return "RUN /python/bin/pip3 install octave_kernel\n"

class Fricas(Kernel):
    def need_lisp(self):
        return True

    def specific_install(self):
        return r"""
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

RUN . /python/bin/activate && \
 	/python/bin/pip3 install wheel && \
 	/python/bin/pip3 install jupyter && \
 	/python/bin/pip3 install requests && \
    /python/bin/pip3 install jfricas
"""

class Maxima(Kernel):
    def need_lisp(self):
        return True

    def get_environment(self):
        return {'MAXIMA_VERSION': '5.47.0'}

    def specific_install(self):
        return r"""
# install maxima
RUN cd /usr/src/ && \
  wget "https://altushost-swe.dl.sourceforge.net/project/maxima/Maxima-source/${MAXIMA_VERSION}-source/maxima-${MAXIMA_VERSION}.tar.gz?viasf=1" -O maxima.tar.gz && \
  tar xf maxima.tar.gz && \
  rm maxima.tar.gz && \
  cd maxima-${MAXIMA_VERSION}/ && \
  ./configure && \
  make -j4 && \
  make install

ADD install.maxima /usr/src

RUN git clone https://github.com/robert-dodier/maxima-jupyter && \
	cd maxima-jupyter/ && \
  maxima -b /usr/src/install.maxima
"""

class Haskell(Kernel):
    def get_dependencies(self):
        return {'libtinfo-dev', 'libzmq3-dev',
                'libcairo2-dev', 'libpango1.0-dev',
                'haskell-stack', 'libmagic-dev',
                'libgsl-dev', 'libblas-dev', 'liblapack-dev'}

    def specific_install(self):
        return r"""
RUN stack upgrade && \
    mkdir -p /root/.stack/global-project && \
    echo -e 'packages: []\nsnapshot: lts-22-10' > /root/.stack/global-project/stack.yaml && \
    git clone https://github.com/gibiansky/IHaskell && \
    cd IHaskell && \
    /python/bin/pip3 install -r requirements.txt && \
    stack install --fast && \
    ~/.local/bin/ihaskell install --stack
"""

class Julia(Kernel):
    def get_environment(self):
        return {'JULIA_MAJOR_VERSION': '1.11',
                'JULIA_VERSION': '1.11.2'
            }

    def specific_install(self):
        return r"""
# install Julia
RUN cd /opt && \
  wget https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MAJOR_VERSION}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz -O julia.tar.gz && \
  tar xf julia.tar.gz && \
  ln -s /opt/julia-${JULIA_VERSION}/bin/julia /usr/local/bin && \
  rm julia.tar.gz

# install Julia for jupyter
ADD install.julia /usr/src/install.julia
RUN julia /usr/src/install.julia
"""

class R(Kernel):
    def get_dependencies(self):
        return {'r-recommended', 'r-cran-ggplot2',
            'r-cran-repr', 'r-cran-pbdzmq', 'r-cran-devtools'}

    def specific_install(self):
        return r"""
# install R for jupyter (IRkernel)
ADD install.R /usr/src/install.R
RUN R -f /usr/src/install.R
"""

class Java(Kernel):
    def get_dependencies(self):
        return {'openjdk-17-jdk-headless'}

    def specific_install(self):
        return r"""
RUN wget https://github.com/allen-ball/ganymede/releases/download/v2.1.2.20230910/ganymede-2.1.2.20230910.jar -O ganymede.jar && \
        java -jar ganymede.jar -i
"""

KNOWN_KERNELS = {
        'python': Python(),
        'octave': Octave(),
        'fricas': Fricas(),
        'maxima': Maxima(),
        'haskell': Haskell(),
        'julia': Julia(),
        'r': R(),
        'java': Java()
    }

DEFAULT_KERNELS = ['python', 'octave']

def parse_cmdline():
    parser = argparse.ArgumentParser(
                prog = "JupyterLab docker image builder",
                description = "Build a JupyterLab docker image with required kernels")
    parser.add_argument('-k', '--kernel', nargs='*', help="Specify required kernels")
    parser.add_argument('--list-kernels', action='store_true', help="List supported kernels")
    parser.add_argument('--ubuntu-version', nargs='?', default='24.04')
    parser.add_argument('-o', '--output', default='Dockerfile.jupyter')
    parser.add_argument('-b', '--build', action='store_true', help="Build the container")
    parser.add_argument('-t', '--tag', nargs='?', default='jupyter', help="Specify image tag")
    return parser.parse_args()

def apt_install(deps):
    sep = " \\\n    "
    install = "RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends"
    return install + " " + sep.join(list(deps)) + "\n"

def get_kernels(keys):
    if keys is None:
        keys = DEFAULT_KERNELS
    for key in keys:
        kernel = KNOWN_KERNELS.get(key, None)
        if kernel is None:
            raise Exception("Unknown kernel: " + key)
        yield kernel

def collect_environment(kernels):
    env = dict()
    for kernel in get_kernels(kernels):
        env.update(kernel.get_environment())
    return env

def need_lisp(kernels):
    for kernel in get_kernels(kernels):
        if kernel.need_lisp():
            return True
    return False

def collect_deps(kernels):
    deps = GENERIC_DEPS.copy()
    if need_lisp(kernels):
        deps.update(LISP_DEPS)
    for kernel in get_kernels(kernels):
        deps.update(kernel.get_dependencies())
    return deps

def generate_dockerfile(args):
    result = HEADER_TEMPLATE.format(
            ubuntu_version = args.ubuntu_version
        )

    env = collect_environment(args.kernel)
    for key, value in env.items():
        result += f"ENV {key} {value}\n"

    deps = collect_deps(args.kernel)
    result += apt_install(deps)

    result += GENERIC_INSTALL

    if need_lisp(args.kernel):
        result += INSTALL_LISP

    for kernel in get_kernels(args.kernel):
        result += kernel.specific_install()

    result += TRAILER

    return result

if __name__ == "__main__":
    args = parse_cmdline()
    if args.list_kernels:
        print(", ".join(list(KNOWN_KERNELS.keys())))
    else:
        with open(args.output, 'w') as f:
            f.write(generate_dockerfile(args))
        if args.build:
            file_dir = dirname(args.output)
            if not file_dir:
                file_dir = "."
            command = f"docker build -t {args.tag} -f {args.output} {file_dir}"
            print("Running:", command)
            subprocess.run(command, shell=True, check=True)
