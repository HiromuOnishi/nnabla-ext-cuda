// Copyright (c) 2017 Sony Corporation. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <nbla/cuda/communicator/multi_process_data_parallel_communicator.hpp>
#include <nbla/cuda/common.hpp>

#include <algorithm>
#include <memory>
#include <cstdlib>

#include "mpi.h"

namespace nbla {

using std::make_shared;


template<typename T>
__global__ void kernel_divide_inplace(const int size, const int n_devices,
    T *dw) {
  NBLA_CUDA_KERNEL_LOOP(i, size) {
    dw[i] /= n_devices;
  }
}


template<typename T>
MultiProcessDataParallelCommunicatorNccl<T>::MultiProcessDataParallelCommunicatorNccl(const Context &ctx) : MultiProcessDataParallelCommunicator<T>(ctx) {}

template<typename T>
MultiProcessDataParallelCommunicatorNccl<T>::~MultiProcessDataParallelCommunicatorNccl() {
  if (this->initialized_) {
    ncclCommDestroy(comm_);
    cudaStreamDestroy(stream_);
  }
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::init() {
  Communicator::init();
  try {

    // MPI init
    MPI_Comm_size(MPI_COMM_WORLD, &size_);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank_);
    device_id_ = rank_;  //TODO address non-ordered devices

    // We have to set our device before NCCL init
    cudaSetDevice(device_id_);
    MPI_Barrier(MPI_COMM_WORLD);

    // Exchange comIds among processes
    ncclGetUniqueId(&comm_id_);
    MPI_Bcast(&comm_id_, NCCL_UNIQUE_ID_BYTES, MPI_CHAR, 0, MPI_COMM_WORLD);

    // Nccl Init
    ncclResult_t ret = ncclCommInitRank(&comm_, size_, comm_id_, rank_);
    if (ret != ncclSuccess) {
      NBLA_ERROR(error_code::target_specific, "ncclCommInitRank failed.");
    }

    // Create stream
    cudaStreamCreateWithFlags(&stream_, cudaStreamNonBlocking);

    this->initialized_ = true;
  } catch (...) {
    NBLA_ERROR(error_code::unclassified, "Communicator init failed.");
  }
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::reduce(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CUDA GPU reduce is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::allreduce(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CUDA GPU allreduce is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::reducescatter(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CUDA GPU reducescatter is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::bcast() {
  NBLA_ERROR(error_code::not_implemented,
      "CUDA GPU bcast is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::allgather() {
  NBLA_ERROR(error_code::not_implemented,
      "CUDA GPU allgather is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::ireduce(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CUDA GPU ireduce is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::iallreduce(bool division) {
  // Sync all devices
  wait_by_device_synchronization();

  // Once sync to prevent the hang where the memcpy occurs during the allreduce.
  this->sync_all_params();

  // Inpalce allreduce
  //TODO: have to override add_context_and_parameters or check context is one
  Context ctx = this->contexts_[0];

  auto func_named_param = this->device_func_named_param_[0];
  auto size = func_named_param.size();

  for (auto elm : func_named_param) {  // function-loop
    VariablePtr vp = elm.second;
    auto n_param = vp->size();

    const T *dw0 = vp->get_grad_pointer<T>(ctx);
    T *dw1 = vp->cast_grad_and_get_pointer<T>(ctx);
    ncclResult_t res = ncclAllReduce(
        dw0, dw1,
        n_param, ncclFloat, ncclSum, //TODO: address ncclFloat
        comm_,
        stream_);
  }

  // Divide using the same streams
  divide_by_num_divices(division);

  // Sync streams
  wait_by_stream_synchronization();
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::ireducescatter(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CUDA GPU ireducescatter is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::ibcast() {
  NBLA_ERROR(error_code::not_implemented,
      "CUDA GPU ibcast is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::iallgather() {
  NBLA_ERROR(error_code::not_implemented,
      "CUDA GPU iallgather is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::reduce_async(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CPU reduce_async is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::allreduce_async(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CPU allreduce_async is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::reducescatter_async(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CPU reducescatter_async is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::bcast_async() {
  NBLA_ERROR(error_code::not_implemented,
      "CPU bcast_async is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::allgather_async() {
  NBLA_ERROR(error_code::not_implemented,
      "CPU allgather_async is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::ireduce_async(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CPU ireduce_async is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::iallreduce_async(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CPU iallreduce_async is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::ireducescatter_async(bool division) {
  NBLA_ERROR(error_code::not_implemented,
      "CPU ireducescatter_async is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::ibcast_async() {
  NBLA_ERROR(error_code::not_implemented,
      "CPU ibcast_async is not implemented.")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::iallgather_async() {
  NBLA_ERROR(error_code::not_implemented,
      "CPU iallgather_async is not implemented.")
}

template<typename T>
vector<string> MultiProcessDataParallelCommunicatorNccl<T>::allowed_array_classes() {
  NBLA_ERROR(error_code::not_implemented,
      "Derived class of MultiProcessDataParallelCommunicatorNccl must implement allowed_array_classes().")
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::wait_by_device_synchronization() {
  cudaDeviceSynchronize();
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::wait_by_stream_synchronization() {
  cudaStreamSynchronize(stream_);
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::divide_by_num_divices(bool division) {
  if (division) {
    //TODO: have to override add_context_and_parameters or check context is one
    Context ctx = this->contexts_[0];
    auto func_named_param = this->device_func_named_param_[0];
    for (auto elm : func_named_param) {
      VariablePtr vp = elm.second;
      T *dw = vp->cast_grad_and_get_pointer<T>(ctx);
      auto n_param = vp->size();
      NBLA_CUDA_LAUNCH_KERNEL_IN_STREAM(
          kernel_divide_inplace, stream_, n_param, size_, dw);
    }
  }
}

template<typename T>
void MultiProcessDataParallelCommunicatorNccl<T>::sync_all_params() {
  //TODO: have to override add_context_and_parameters or check context is one
  Context ctx = this->contexts_[0];
  auto func_named_param = this->device_func_named_param_[0];
  auto size = func_named_param.size();

  for (auto elm : func_named_param) {          // function-loop
    VariablePtr vp = elm.second;

    // If the arrays are different, output the warning.
    this->check_array_class(ctx, vp);

    // Sync
    vp->get_grad_pointer<T>(ctx);
  }
}

template class MultiProcessDataParallelCommunicatorNccl<float>;
}