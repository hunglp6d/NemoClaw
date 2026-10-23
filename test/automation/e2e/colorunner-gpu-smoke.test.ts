// SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { readYaml } from "../../helpers/e2e-workflow-contract";

function runGpuStep(exitCode: number) {
  const workflow = readYaml<{ jobs: { gpu: { steps: Array<{ run: string }> } } }>(
    ".github/workflows/colorunner-gpu-smoke.yml",
  );
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "colorunner-gpu-smoke-"));
  try {
    fs.writeFileSync(
      path.join(directory, "nvidia-smi"),
      '#!/bin/sh\nprintf "NVIDIA GB10\\n"\nexit "$GPU_SMOKE_EXIT"\n',
      { mode: 0o755 },
    );
    return spawnSync("bash", ["-e", "-o", "pipefail", "-c", workflow.jobs.gpu.steps[0].run], {
      cwd: directory,
      env: {
        ...process.env,
        PATH: `${directory}:${process.env.PATH}`,
        GPU_SMOKE_EXIT: `${exitCode}`,
      },
      encoding: "utf8",
      timeout: 5_000,
      killSignal: "SIGKILL",
    });
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

describe("Colorunner GPU smoke", () => {
  it("reports GPU output when the tool succeeds", () => {
    const result = runGpuStep(0);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("NVIDIA GB10");
  });

  it("fails when the GPU tool fails", () => {
    expect(runGpuStep(42).status).toBe(42);
  });
});
