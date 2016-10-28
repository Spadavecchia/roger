# Roger: Multi-tenant job processor

[![Build Status](https://travis-ci.org/arjan/decorator.png?branch=master)](https://travis-ci.org/bettyblocks/roger)


**TODO: Add description**

## Feature checklist

- [x] Multi-tentant architecture
- [x] Based on Rabbitmq
- [x] Per-queue concurrency control
- [x] Jobs cancellation (both in the queue and while running)
- [x] Option to enforce per-application job uniqueness
- [x] Option to enforce job uniqueness during execution
- [ ] All operations are cluster-aware
- [ ] Pausing / unpausing work queues
- [ ] Retry w/ exponential backoff
- [ ] Management API (phoenix mountable); return info from each node (rabbitmq pubsub?)
- [ ] Documentation


## Configuration

Roger can be configured with callback modules which invoke functions
on various places in the application's life cycle.
