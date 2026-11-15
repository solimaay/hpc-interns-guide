# 05 - Containers

Chapter 10. A hands-on introduction to containers with Podman, with Docker comparisons at each step and a summary table at the end.

Prerequisite: chapters 1 to 5 ([01-sysadmin-foundations](../01-sysadmin-foundations/README.md)). Only the optional Part 7 (a container as a Slurm job) needs chapter 7 ([03-slurm](../03-slurm/README.md)).

## Tools

| Tool | Where it comes from | What it does |
|---|---|---|
| `provision.sh` | run with `vagrant provision --provision-with containers` | Installs Podman, prepares rootless Podman for `vagrant`, and (login node) saves the practice image to `/shared/containers-lab/rockylinux-9.tar`. |
| `container-verify` | installed by `vagrant up` and by the provisioner | Checks that this node is ready: Podman, subordinate IDs, a rootless test container, SELinux boolean, the staged image. |

## Chapter 10 - Containers with Podman

Start with:

```bash
vagrant provision login    --provision-with containers
vagrant provision compute1 --provision-with containers
vagrant ssh login -c container-verify
```

Then follow [the chapter](chapters/10-containers.md).

## Notes

- Everything is rootless, as the user `vagrant`. The lab accounts `alice`, `bob` and `carol` have NFS home directories, which rootless Podman cannot use for its image store, so the chapter does not use them.
- The practice image is `docker.io/library/rockylinux:9` (about 180 MB). The staged tar file lets the chapter work without a registry.
- Docker is not installed. The comparisons are reading notes only.

## Reset

Restore the snapshot you took before the chapter, or run `podman rm -af; podman rmi -af` on each node.
