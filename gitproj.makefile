# By default, find all git projects under this
PWD=$(shell pwd)
BaseDir?=$(PWD)
GitProjFile?=.gitproj

JULIA?=$(shell which julia)

# Find path to this makefile for use in `usage` target.
# See https://stackoverflow.com/questions/18136918/how-to-get-current-relative-directory-of-your-makefile
mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(patsubst %/,%,$(dir $(mkfile_path)))

.gitproj: $(current_dir)/gitproj.jl
	$(JULIA) -L $< -e "exit(emitGitProj())" -- $(BaseDir) > $(BaseDir)/.gitproj.tmp
	mv $(BaseDir)/.gitproj.tmp $(BaseDir)/.gitproj

emitGitProj: $(current_dir)/gitproj.jl
	$(JULIA) -L $< -e "exit($@())" -- $(BaseDir)

diffGitProj: $(current_dir)/gitproj.jl
	$(JULIA) -L $< -e "exit($@())" -- $(BaseDir)

findProjects: $(current_dir)/gitproj.jl
	$(JULIA) -L $< -e "exit($@())" -- $(BaseDir)

updateProjects: $(current_dir)/gitproj.jl
	$(JULIA) -L $< -e "exit($@())" -- $(BaseDir)

cloneProjects: $(current_dir)/gitproj.jl
	$(JULIA) -L $< -e "exit($@())" -- $(BaseDir)

statusProjects: $(current_dir)/gitproj.jl
	$(JULIA) -L $< -e "exit($@())" -- $(BaseDir)

dirtyProjects: $(current_dir)/gitproj.jl
	$(JULIA) -L $< -e "exit($@())" -- $(BaseDir)

pushProjects: $(current_dir)/gitproj.jl
	$(JULIA) -L $< -e "exit($@())" -- $(BaseDir)

shell: $(current_dir)/gitproj.jl
	$(JULIA) -L $< -i

# cloneProjects without Julia installation
cloneAll: $(BaseDir)/$(GitProjFile)
	cat $< | \
	grep --invert-match '= &' | \
	grep --invert-match '^#' | \
	cut  --delimiter='&' --fields=1 | \
	sed 's/\([^=]*\)=\([^=]*\)/\2 \1/' | \
	xargs --max-args=2 git clone
	

usage:
	@echo "usage: make -f $(mkfile_path) COMMANDS [BaseDir=$(BaseDir)] [JULIA=$(JULIA)] [GitProjFile=$(GitProjFile)]"
	@echo "    where COMMANDS are one or more of"
	@echo "    - .gitproj: Update the file under BaseDir/$(GitProjFile) with all git repositories under BaseDir."
	@echo "    - emitGitProj: Show the .gitproj file that the previous command would emit."
	@echo "    - diffGitProj: Show a listing of all expected and existing git repositories. If a repository"
	@echo "                   exists but is not expected, prefix it with '+'. If a repository is expected but"
	@echo "                   is missing, prefix it with '-'."
	@echo "    - findProjects: Find all git repositories under BaseDir."
	@echo "    - updateProjects: Pull and update current branch of all git projects under BaseDir."
	@echo "    - cloneProjects: Clone all git projects listed in BaseDir/$(GitProjFile)."
	@test true || echo "    - statusProjects: Detailed status information for all git projects under BaseDir."
	@echo "    - dirtyProjects: Summary (dirty/clean) status for all git projects under BaseDir."
	@echo "    - pushProjects: Push all git projects under BaseDir."
	@echo "    - shell: Load the project management functions and drop into a Julia REPL."
	@echo ""
	@echo "    To set a custom Julia version, set the JULIA variable as in the above usage message."
	@echo "    Using the make option \"-B\" to unconditionally remake the $(GitProjFile) file is recommended."
	@echo ""
	@echo "    *Note* gitproj files may have comments and configuration commands; lines starting with"
	@echo "    a \"#\" are considered comments. Commands in gitproj files are of the form"
	@echo "        Directive=Parameters"
	@echo "    Current supported directives are IgnoreStems and IgnorePaths. IgnoreStems is a comma-"
	@echo "    separated list of prefixes; a directory starting with one of these prefixes will be"
	@echo "    skipped. IgnorePath is a particular subdirectory to be skipped when searching for git"
	@echo "    repositories to skip."
	@echo ""
	@echo "    Comments at the beginning of the file will be retained on regenerating the gitproj file."
