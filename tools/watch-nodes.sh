#!/usr/bin/env bash

while :
do
  date
  kubectl get nodes -o wide
  kubectl describe nodes
  sleep 1
done
