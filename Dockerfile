ARG IMAGE_NAME=nvidia/cuda
FROM ${IMAGE_NAME}:12.6.1-cudnn-devel-ubuntu24.04 as base

FROM base as base-amd64

ENV NV_CUDNN_VERSION 9.3.0.75-1
ENV NV_CUDNN_PACKAGE_NAME libcudnn9-cuda-12
ENV NV_CUDNN_PACKAGE libcudnn9-cuda-12=${NV_CUDNN_VERSION}
ENV NV_CUDNN_PACKAGE_DEV libcudnn9-dev-cuda-12=${NV_CUDNN_VERSION}

FROM base as base-arm64

ENV NV_CUDNN_VERSION 9.3.0.75-1
ENV NV_CUDNN_PACKAGE_NAME libcudnn9-cuda-12
ENV NV_CUDNN_PACKAGE libcudnn9-cuda-12=${NV_CUDNN_VERSION}
ENV NV_CUDNN_PACKAGE_DEV libcudnn9-dev-cuda-12=${NV_CUDNN_VERSION}

FROM base-${TARGETARCH}

ARG TARGETARCH

LABEL maintainer "utopeadia <https://github.com/utopeadia>"
LABEL com.nvidia.cudnn.version="${NV_CUDNN_VERSION}"

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV ROOT_PASSWORD=change_this_password
ENV UBUNTU_PASSWORD=change_this_password
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Jupyter Notebook 配置环境变量
ENV JUPYTER_PASSWORD=""
ENV JUPYTER_TOKEN=""
ENV JUPYTER_PORT=8888
ENV JUPYTER_NOTEBOOK_DIR="/root"

RUN apt-get update && apt-get install -y \
    bash \
    wget \
    bzip2 \
    ca-certificates \
    sudo \
    openssh-server \
    vim \
    git \
    curl \
    tmux \
    build-essential \
    locales \
    && rm -rf /var/lib/apt/lists/*

# 设置语言环境
RUN echo "ubuntu:${UBUNTU_PASSWORD}" | chpasswd
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# 设置SSH
RUN mkdir /var/run/sshd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd


# 使用 ubuntu 用户安装 miniconda 和配置 jupyter
USER ubuntu
ENV CONDA_DIR /home/ubuntu/miniconda3
RUN if [ "$TARGETARCH" = "amd64" ]; then \
    wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
    wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O ~/miniconda.sh; \
    fi && \
    /bin/bash ~/miniconda.sh -b -p $CONDA_DIR && \
    rm ~/miniconda.sh && \
    echo ". $CONDA_DIR/etc/profile.d/conda.sh" >> ~/.bashrc
    
RUN conda config --add channels conda-forge \
    && conda create -n jupyter_env -c conda-forge jupyter -y \
    && conda clean -afy

# 创建 Jupyter Notebook 配置文件 (ubuntu 用户)
RUN mkdir -p ~/.jupyter && \
    echo "c.NotebookApp.ip = '0.0.0.0'" >> ~/.jupyter/jupyter_notebook_config.py && \
    echo "c.NotebookApp.port = ${JUPYTER_PORT}" >> ~/.jupyter/jupyter_notebook_config.py && \
    echo "c.NotebookApp.notebook_dir = '/home/ubuntu'" >> ~/.jupyter/jupyter_notebook_config.py # 修改默认目录

RUN if [ -n "${JUPYTER_PASSWORD}" ]; then \
    echo -e "from jupyter_server.auth import passwd\n\
    password = '${JUPYTER_PASSWORD}'\n\
    hash = passwd(password)\n\
    print(f\"c.NotebookApp.password = '{hash}'\")" | python >> ~/.jupyter/jupyter_notebook_config.py; \
    fi

RUN if [ -n "${JUPYTER_TOKEN}" ]; then \
    echo "c.NotebookApp.token = '${JUPYTER_TOKEN}'" >> ~/.jupyter/jupyter_notebook_config.py; \
    fi

RUN ssh-keygen -t rsa -b 4096 -f /home/ubuntu/.ssh/id_rsa -N "" -q

USER root

RUN echo '#!/bin/bash\n\
    if [ ! -f "/root/.ssh/ssh_host_rsa_key" ]; then\n\
    ssh-keygen -A\n\
    fi\n\
    echo "root:${ROOT_PASSWORD}" | chpasswd\n\
    echo "ubuntu:${UBUNTU_PASSWORD}" | chpasswd\n\
    service ssh start\n\
    # 以 ubuntu 用户启动 jupyter\n\
    su - ubuntu -c "\n\
        source /home/ubuntu/miniconda3/etc/profile.d/conda.sh\n\
        conda activate jupyter_env\n\
        jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token=\"\" --NotebookApp.password=\"\"\n\
    "\n\
    ' > /start.sh && chmod +x /start.sh


# 暴露SSH和Jupyter Notebook端口
EXPOSE 22 8888

CMD ["/start.sh"]
