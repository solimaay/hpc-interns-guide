# Chapter 10 - Containers with Podman

About 1.5 hours. You work on `login` and `compute1` as the user `vagrant`.

A container runs a program together with everything it needs, in its own private view of the system. HPC users ask for them constantly ("it works on my laptop, can you run it on the cluster?"), so an admin has to know what they are and how they fail. You use Podman, and each step notes how Docker differs.

## What you will learn

- Say what a container is, and what it is not (a VM).
- Pull images and run, list, inspect and remove containers.
- See how file ownership and SELinux behave when you share a folder with a container.
- Build a small image and run it on both nodes.
- Run a task as a container: input in, output out, exit code back.

## Before you start

- Chapters 1 to 5 are done.
- Prepare the nodes, `login` first, from your host in the lab folder:

  ```bash
  vagrant provision login    --provision-with containers
  vagrant provision compute1 --provision-with containers
  ```

- On each node, as `vagrant`: `container-verify` should end with `Result: CONTAINERS READY`.
- Take a snapshot: `vagrant snapshot save before-containers`.
- Images are pulled from a public registry. If you have no internet access, load the staged copy instead whenever a step pulls `alpine`:

  ```bash
  podman load -i /shared/containers-lab/alpine.tar
  ```

## Part 1 - What is a container?

On `login`:

```bash
cat /etc/os-release | head -2
podman run --rm docker.io/library/alpine:3.20 cat /etc/os-release | head -2
```

The first command shows Rocky Linux. The second shows Alpine Linux, yet you never installed or booted Alpine. `--rm` removes the container when it exits.

A container is an ordinary process with a private view of files, processes and network, made with kernel features (namespaces and cgroups). It shares the host's kernel. A VM has its own kernel. See it from the host:

```bash
podman run -d --name sleeper docker.io/library/alpine:3.20 sleep 600
ps -ef | grep '[s]leep 600'
podman ps
uname -r
podman exec sleeper uname -r
```

You see the container's `sleep` in the host's `ps`, and both kernels report the same version.

> **Docker comparison.** Docker sends every command to a root-owned daemon (`dockerd`), and containers are its children. Podman has no daemon: `podman run` forks the container directly, so it belongs to you. Check with `pstree -p $$` while one runs.

## Part 2 - Images and the life of a container

An **image** is the read-only template; a **container** is a running (or stopped) instance of it.

```bash
podman images
podman ps -a
podman logs sleeper
podman exec -it sleeper sh
```

Inside the container, run `hostname`, `id` and `ps`, then `exit`. You are `root` in there; keep that in mind for Part 3.

Stop and remove it, then run one that just prints and exits:

```bash
podman stop -t 1 sleeper
podman rm sleeper
podman run --name once docker.io/library/alpine:3.20 echo hello
podman ps -a
podman rm once
```

`ps -a` shows stopped containers too. Without `--rm` they stay until you remove them, which is how disks fill up. `podman system df` shows what images and containers use.

> **Docker comparison.** These commands are the same; `alias docker=podman` works. Podman wants full image names (`docker.io/library/alpine`) or asks which registry to use for a short name.

## Part 3 - Your files in a container

Make a folder on the node and mount it into a container with `-v host:container`:

```bash
mkdir -p ~/work
podman run --rm -v ~/work:/data docker.io/library/alpine:3.20 sh -c 'echo hi > /data/a.txt'
```

It fails with `Permission denied`, although you own `~/work`. This is SELinux (Chapter 4): the folder's label is not one containers may write. Read it, then ask Podman to relabel the folder for the container with `:Z`:

```bash
ls -Zd ~/work
podman run --rm -v ~/work:/data:Z docker.io/library/alpine:3.20 sh -c 'echo hi > /data/a.txt'
ls -Zd ~/work
ls -ln ~/work/a.txt
id -u
```

It works now. The label changed to `container_file_t`, and the file belongs to **your** user ID, not to root, although the process in the container was root. Rootless Podman maps container root to you:

```bash
podman unshare cat /proc/self/uid_map
```

Read the first line: container UID 0 is your UID, and the next range comes from `/etc/subuid`.

> **Docker comparison.** Docker's daemon runs as real root, so the same file would be owned by `root` on the host, and a container started with `-v /:/host` has full root access to the machine. This is the main reason HPC sites avoid Docker on shared nodes.

Can a container use `/shared`? Try it on `compute1`, where `/shared` is an NFS mount. The provisioner turned on the SELinux boolean `virt_use_nfs` for this:

```bash
podman run --rm -v /shared/scratch:/data docker.io/library/alpine:3.20 sh -c 'echo from-container > /data/c-demo.txt'
ls -ln /shared/scratch/c-demo.txt
```

It works, and the file belongs to your user ID again. Do not use `:Z` on NFS; relabeling does not work there.

On `login` the same command is denied: there `/shared` is a plain local folder (the NFS *server* side), labelled `default_t`, and the NFS boolean does not apply. Do not relabel it with `:Z`; that would change the label of the whole export. Containers are meant to run on compute nodes anyway.

## Part 4 - Build your own image

An image is built from a recipe called a **Containerfile**. Make one:

```bash
mkdir -p ~/hello && cd ~/hello
cat > hello.sh <<'EOS'
#!/bin/sh
echo "Hello from $(hostname), running $(. /etc/os-release; echo $PRETTY_NAME)"
EOS
cat > Containerfile <<'EOS'
FROM docker.io/library/alpine:3.20
COPY hello.sh /usr/local/bin/hello.sh
RUN chmod +x /usr/local/bin/hello.sh
CMD ["/usr/local/bin/hello.sh"]
EOS
podman build -t hello:1 .
podman run --rm --hostname "$(hostname)" hello:1
```

Each line is a layer. Change the greeting in `hello.sh` and build again as `hello:2`. The `FROM` layer is reused; every step from the changed `COPY` onward is rebuilt, which is why you put what changes least at the top. `podman history hello:2` lists the layers.

> **Docker comparison.** `docker build` reads a `Dockerfile`; Podman reads `Containerfile` or `Dockerfile`. Podman builds without a daemon (Buildah is the engine under it).

## Part 5 - The same image on two nodes

The image lives in your local store on `login`; `compute1` does not have it. Move it through shared storage:

```bash
podman save -o /shared/scratch/hello-1.tar hello:1       # login
```

```bash
podman load -i /shared/scratch/hello-1.tar               # compute1
podman run --rm --hostname "$(hostname)" hello:1   # compute1
```

The output names `compute1`, because `--hostname` passes the node name in (a container otherwise gets a random ID as its hostname), but it is the same Alpine. That is the point of a container: one image behaves the same everywhere. Compare `podman images` on both nodes.

> **Docker comparison.** `docker save` and `docker load` work the same way, and both need the daemon running on each node. Real sites use a registry instead of tar files; `podman push` and `podman pull` talk to one.

## Part 6 - Example: run a task as a container

A batch job is a command with an input, an output and an exit code. A container suits it: the environment is the same wherever it runs, and nothing is left behind. Try it on `login`.

Make an input file and a small task script in a folder:

```bash
mkdir -p ~/job
printf 'banana\napple\ncherry\napple\n' > ~/job/input.txt
cat > ~/job/task.sh <<'EOS'
#!/bin/sh
sort /job/input.txt | uniq -c > /job/output.txt
EOS
```

Run it as a container. The folder is the only thing shared with it:

```bash
podman run --rm -v ~/job:/job:Z docker.io/library/alpine:3.20 sh /job/task.sh
echo "exit=$?"
cat ~/job/output.txt
```

You get `2 apple`, `1 banana`, `1 cherry`. Notice the steps and what each one is for:

| Step | Why |
|---|---|
| Input goes in through the mounted folder | the container itself is thrown away |
| Output comes back through the same folder | `--rm` deletes the container, but the file stays on the host |
| `--rm` | no stopped containers pile up |
| `$?` is the container's exit code | this is how a script, or later a scheduler, knows whether the task worked |

Check that failure is visible too:

```bash
podman run --rm docker.io/library/alpine:3.20 sh -c 'exit 3'; echo "exit=$?"
```

It prints `exit=3`. A scheduler would run this same one command for you on a compute node; as in Part 5, that node needs the image first.

## Part 7 - Clean up

On both nodes:

```bash
podman rm -af
podman rmi -af
rm -f /shared/scratch/hello-1.tar /shared/scratch/c-demo.txt   # on compute1 the last one
rm -rf ~/work ~/hello ~/job
podman system df
```

`container-verify` should still say `CONTAINERS READY`. (It loads the practice image again; that is fine.)

## Docker and Podman at a glance

| | Podman | Docker |
|---|---|---|
| Architecture | no daemon; containers are your processes | root daemon `dockerd` runs them |
| Default privilege | rootless; container root maps to your user | root daemon; users in the `docker` group are effectively root |
| Command line | `podman ...` | `docker ...` (nearly identical) |
| Build file | `Containerfile` or `Dockerfile` | `Dockerfile` |
| Multi-container | `podman compose`, pods, Kubernetes YAML | Docker Compose |
| Run at boot | systemd units (Quadlet) | restart policies in the daemon |
| Fit for shared HPC nodes | acceptable, rootless | not recommended |
| What HPC sites often use for user jobs | Apptainer (not covered here) | not on shared compute nodes |

## Check yourself

<details><summary>1. A container shows `Rocky` on the host and `Alpine` inside. Is it a VM? How do you know?</summary>

No. It is a process sharing the host kernel: `uname -r` is the same inside and outside, and the container's processes appear in the host's `ps`.
</details>

<details><summary>2. A user mounts their folder into a container and gets "Permission denied", although they own it. What do you check?</summary>

SELinux first (`ls -Z`, the audit log). The fix is the `:Z` option for a local folder; NFS needs the `virt_use_nfs` boolean instead.
</details>

<details><summary>3. A container running as root creates a file in a mounted folder. Who owns it on the host with rootless Podman? With Docker?</summary>

Rootless Podman: the user who ran it. Docker: `root`.
</details>

<details><summary>4. Why do HPC sites prefer Apptainer to Docker on compute nodes?</summary>

Docker needs a root daemon, and access to it is root access. Apptainer runs as the user and ships the image as one file. It is outside this lab, but you will meet it on real clusters.
</details>

<details><summary>5. `podman ps` is empty but the disk is filling up. Where do you look?</summary>

`podman ps -a` for stopped containers, `podman images` for unused images, and `podman system df` for the totals. `podman system prune` clears what is unused.
</details>

## If you are stuck

- `container-verify` names the missing piece.
- `Error: ... newuidmap` or `cannot set up namespace`: the `vagrant` user has no subordinate ID range; run the provisioner again.
- A pull hangs or fails: no internet or a registry limit. Use `podman load -i /shared/containers-lab/alpine.tar`.
- To start over: `vagrant snapshot restore before-containers`.

## Next

Chapter 9, [node health checks](../../04-health-monitoring/README.md), pairs well with this one: run `node-health` while a container is busy.
