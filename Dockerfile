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

ARG TARGETARCH

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    ROOT_PASSWORD=change_this_password \
    USERNAME=gasman \
    PASSWORD=change_this_password \
    PUID=1000 \
    PGID=1000 \
    JUPYTER_PASSWORD="" \
    JUPYTER_TOKEN="" \
    JUPYTER_PORT=8888 \
    JUPYTER_NOTEBOOK_DIR="/home/$USERNAME"

RUN groupadd --gid $PGID $USERNAME \
    && useradd --uid $PUID --gid $PGID -m $USERNAME \
    && echo "$USERNAME:$PASSWORD" | chpasswd \
    && adduser $USERNAME sudo \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers


# Install necessary packages
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

# Set up locale
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8 \
    LANGUAGE en_US:en \
    LC_ALL en_US.UTF-8

# Configure SSH
RUN mkdir /var/run/sshd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# Install Miniconda for the user
ENV CONDA_DIR /home/$USERNAME/miniconda3
USER $USERNAME
WORKDIR /home/$USERNAME
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh \
    && /bin/bash ~/miniconda.sh -b -p $CONDA_DIR \
    && rm ~/miniconda.sh \
    && ln -s $CONDA_DIR/etc/profile.d/conda.sh /home/$USERNAME/.bashrc \
    && echo ". $CONDA_DIR/etc/profile.d/conda.sh" >> /home/$USERNAME/.bashrc \
    && echo "conda activate base" >> /home/$USERNAME/.bashrc \
    && $CONDA_DIR/bin/conda create -n jupyter_env -c conda-forge jupyter -y \
    && $CONDA_DIR/bin/conda clean -afy

# Configure Jupyter Notebook
RUN mkdir -p /home/$USERNAME/.jupyter \
    && echo "c.NotebookApp.ip = '0.0.0.0'" >> /home/$USERNAME/.jupyter/jupyter_notebook_config.py \
    && echo "c.NotebookApp.port = ${JUPYTER_PORT}" >> /home/$USERNAME/.jupyter/jupyter_notebook_config.py \
    && echo "c.NotebookApp.notebook_dir = '${JUPYTER_NOTEBOOK_DIR}'" >> /home/$USERNAME/.jupyter/jupyter_notebook_config.py \
    && echo "c.NotebookApp.allow_root = True" >> /home/$USERNAME/.jupyter/jupyter_notebook_config.py

RUN if [ -n "${JUPYTER_PASSWORD}" ]; then \
        echo -e "from jupyter_server.auth import passwd\n\
        password = '${JUPYTER_PASSWORD}'\n\
        hash = passwd(password)\n\
        print(f\"c.NotebookApp.password = '{hash}'\")" | python >> /home/$USERNAME/.jupyter/jupyter_notebook_config.py; \
    fi

RUN if [ -n "${JUPYTER_TOKEN}" ]; then \
        echo "c.NotebookApp.token = '${JUPYTER_TOKEN}'" >> /home/$USERNAME/.jupyter/jupyter_notebook_config.py; \
    fi

# Expose SSH and Jupyter Notebook ports
EXPOSE 22 8888

# Create startup script
USER root
RUN echo '#!/bin/bash\n\
    if [ ! -f "/home/$USERNAME/.ssh/ssh_host_rsa_key" ]; then\n\
        ssh-keygen -A\n\
    fi\n\
    echo "$USERNAME:$USERNAME" | chpasswd\n\
    service ssh start\n\
    sudo -u $USERNAME -E /bin/bash -c "source /home/$USERNAME/miniconda3/etc/profile.d/conda.sh && conda activate jupyter_env && jupyter notebook --ip=0.0.0.0 --port=${JUPYTER_PORT} --no-browser --allow-root --NotebookApp.token=${JUPYTER_TOKEN} --NotebookApp.password=${JUPYTER_PASSWORD}"\n\
    ' > /start.sh && chmod +x /start.sh

CMD ["/start.sh"]
