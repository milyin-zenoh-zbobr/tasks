# Task and config repository for `zbobr` tool

The [zbobr](https://github.com/milyin/zbobr/) orchectrator can

- read tasks in the github repository assigned to the `zbobr` using label
- solve task step by step by running different roles (planner, worker, reviewer, etc)
- make `PR` with the solution

This repository contains two separate things which are just convenient to keep in one place, but that's not necessary:

- Configuration files and prompts for `zbobr` instances, each in separate directory. Each instance targets only one repository.
- Github issues which are processed by these instances, the processing reports (in the separate branch in order not to interfere with config's history)

Steps to configure the orchestrator

- Create access token for giving zbobr access to the tasks (issues) repository. It will use it to read and modify the tasks and create reports in it. It also makes sense to use the same access token to pull the configuration and prompts from the repository.
  - Open `Settings` -> `Developer Settings` -> `Personal access tokens` -> `Fine-grained tokens` -> button `Generate new token`
  - Name the token, e.g. `zbobr-tasks`
  - Set resource owner to correct organization. It's convenient to create dedicated organization for this instead of using own account
  - Give access only to this repository for better safety
  - Add the following permissions:
    - Issues: R/W
    - Contents: R/W
  - Store the token in the root .env file 

- On the fresh machine (no need to login with own github account) pull this repository using token above

- Create access token for giving zbobr access to the repository to work on. For safety create separate token for each repository. 
