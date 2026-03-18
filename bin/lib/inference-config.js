// SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

const INFERENCE_ROUTE_URL = "https://inference.local/v1";
const DEFAULT_CLOUD_MODEL = "nvidia/nemotron-3-super-120b-a12b";
const DEFAULT_OLLAMA_MODEL = "nemotron-3-nano:30b";
const DEFAULT_ROUTE_PROFILE = "inference-local";
const DEFAULT_ROUTE_CREDENTIAL_ENV = "OPENAI_API_KEY";
const MANAGED_PROVIDER_ID = "inference";

function getProviderSelectionConfig(provider, model) {
  switch (provider) {
    case "nvidia-nim":
      return {
        endpointType: "custom",
        endpointUrl: INFERENCE_ROUTE_URL,
        ncpPartner: null,
        model: model || DEFAULT_CLOUD_MODEL,
        profile: DEFAULT_ROUTE_PROFILE,
        credentialEnv: DEFAULT_ROUTE_CREDENTIAL_ENV,
      };
    case "vllm-local":
      return {
        endpointType: "custom",
        endpointUrl: INFERENCE_ROUTE_URL,
        ncpPartner: null,
        model: model || "vllm-local",
        profile: DEFAULT_ROUTE_PROFILE,
        credentialEnv: DEFAULT_ROUTE_CREDENTIAL_ENV,
      };
    case "ollama-local":
      return {
        endpointType: "custom",
        endpointUrl: INFERENCE_ROUTE_URL,
        ncpPartner: null,
        model: model || DEFAULT_OLLAMA_MODEL,
        profile: DEFAULT_ROUTE_PROFILE,
        credentialEnv: DEFAULT_ROUTE_CREDENTIAL_ENV,
      };
    default:
      return null;
  }
}

function getOpenClawPrimaryModel(provider, model) {
  const resolvedModel =
    model || (provider === "ollama-local" ? DEFAULT_OLLAMA_MODEL : DEFAULT_CLOUD_MODEL);
  return resolvedModel ? `${MANAGED_PROVIDER_ID}/${resolvedModel}` : null;
}

module.exports = {
  DEFAULT_CLOUD_MODEL,
  DEFAULT_OLLAMA_MODEL,
  DEFAULT_ROUTE_CREDENTIAL_ENV,
  DEFAULT_ROUTE_PROFILE,
  INFERENCE_ROUTE_URL,
  MANAGED_PROVIDER_ID,
  getOpenClawPrimaryModel,
  getProviderSelectionConfig,
};
