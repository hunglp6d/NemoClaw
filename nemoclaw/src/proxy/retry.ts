// SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

interface Choice {
  finish_reason?: string;
}

interface CompletionResponse {
  choices?: Choice[];
}

/**
 * Check whether a non-streaming completion response was truncated due to
 * token length, indicating the client should retry.
 */
export function shouldRetry(response: Record<string, unknown>): boolean {
  const parsed = response as unknown as CompletionResponse;
  if (!Array.isArray(parsed.choices)) return false;
  return parsed.choices.some((c) => c.finish_reason === "length");
}

/**
 * Scan an SSE data line for `finish_reason: "length"`.
 * Returns true when the chunk signals truncation.
 */
export function shouldRetryStreamChunk(dataLine: string): boolean {
  try {
    const parsed = JSON.parse(dataLine) as CompletionResponse;
    if (!Array.isArray(parsed.choices)) return false;
    return parsed.choices.some((c) => c.finish_reason === "length");
  } catch {
    return false;
  }
}
