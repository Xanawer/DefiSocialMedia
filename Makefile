.PHONY: migrate test compile setup

migrate: setup
	truffle migrate --reset

test: setup
	truffle test

compile: setup
	trufle compile

setup:
	npm i