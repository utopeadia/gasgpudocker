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
ENV USER_NAME=ubuntu
ENV USER_PASSWORD=change_this_password
ENV ROOT_PASSWORD=change_this_password
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Jupyter Notebook 配置环境变量
ENV JUPYTER_PASSWORD=""
ENV JUPYTER_TOKEN=""
ENV JUPYTER_PORT=8888
ENV JUPYTER_NOTEBOOK_DIR="/home/${USER_NAME}/notebooks"

RUN apt-get update && apt-get install -y \
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
    
# 创建非 root 用户并配置 sudo 权限
RUN useradd -m ${USER_NAME} && \
    echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd && \
    usermod -aG sudo ${USER_NAME} && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    
# 设置语言环境
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# 设置SSH
RUN mkdir /var/run/sshd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

USER ${USER_NAME}
ENV CONDA_DIR /home/${USER_NAME}/miniconda3

# 安装 Miniconda
RUN if [ "$TARGETARCH" = "amd64" ]; then \
    wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
    wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O ~/miniconda.sh; \
    fi && \
    /bin/bash ~/miniconda.sh -b -p $CONDA_DIR && \
    rm ~/miniconda.sh && \
    ln -s $CONDA_DIR/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". $CONDA_DIR/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc

ENV PATH=$CONDA_DIR/bin:$PATH

RUN conda create -n jupyter_env -c conda-forge jupyter -y && \
    conda clean -afy


# 创建并激活 Jupyter 环境
RUN conda create -n jupyter_env -c conda-forge jupyter -y && \
    conda clean -afy

# 创建 Jupyter Notebook 配置文件
RUN mkdir -p /home/${USER_NAME}/.jupyter && \
    echo "c.NotebookApp.ip = '0.0.0.0'" >> /home/${USER_NAME}/.jupyter/jupyter_notebook_config.py && \
    echo "c.NotebookApp.port = ${JUPYTER_PORT}" >> /home/${USER_NAME}/.jupyter/jupyter_notebook_config.py && \
    echo "c.NotebookApp.notebook_dir = '${JUPYTER_NOTEBOOK_DIR}'" >> /home/${USER_NAME}/.jupyter/jupyter_notebook_config.py && \
    echo "c.NotebookApp.allow_root = True" >> /home/${USER_NAME}/.jupyter/jupyter_notebook_config.py

# 切换回 root 用户以设置启动脚本和权限
USER root

# 暴露 SSH 和 Jupyter Notebook 端口
EXPOSE 22 8888

# 创建启动脚本
RUN echo '#!/bin/bash\n\
    echo "root:${ROOT_PASSWORD}" | chpasswd\n\
    service ssh start\n\
    su - ${USER_NAME} -c "source /home/${USER_NAME}/miniconda3/etc/profile.d/conda.sh && conda activate jupyter_env && jupyter notebook --ip=0.0.0.0 --port=${JUPYTER_PORT} --no-browser --allow-root"\n\
    ' > /start.sh && chmod +x /start.sh

# 切换到用户主目录
WORKDIR /home/${USER_NAME}

CMD ["/start.sh"]
