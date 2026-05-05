// SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

import { beforeEach, describe, expect, it, vi } from "vitest";

import { OnboardCliCommand } from "./onboard-cli-commands";
import { runOnboardAction } from "./global-cli-actions";

vi.mock("./global-cli-actions", () => ({
  runOnboardAction: vi.fn().mockResolvedValue(undefined),
  runSetupAction: vi.fn().mockResolvedValue(undefined),
  runSetupSparkAction: vi.fn().mockResolvedValue(undefined),
}));

const rootDir = process.cwd();

describe("onboard oclif command", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects mutually exclusive resume and fresh flags before dispatch", async () => {
    await expect(OnboardCliCommand.run(["--resume", "--fresh"], rootDir)).rejects.toThrow(
      /resume|fresh/,
    );

    expect(runOnboardAction).not.toHaveBeenCalled();
  });

  it("forwards installer automation and sandbox GPU flags to legacy onboard parsing", async () => {
    await OnboardCliCommand.run(
      [
        "--non-interactive",
        "--yes-i-accept-third-party-software",
        "--yes",
        "--sandbox-gpu",
        "--sandbox-gpu-device",
        "nvidia.com/gpu=0",
      ],
      rootDir,
    );

    expect(runOnboardAction).toHaveBeenCalledWith([
      "--non-interactive",
      "--sandbox-gpu",
      "--sandbox-gpu-device",
      "nvidia.com/gpu=0",
      "--yes",
      "--yes-i-accept-third-party-software",
    ]);
  });
});
