#!/usr/bin/env python3
import argparse
import json
import sys
import urllib.request


def mcp_request(endpoint: str, request_id: int, method: str, params: dict):
    payload = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
        "params": params,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        endpoint,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        body = response.read().decode("utf-8")
        parsed = json.loads(body)
        if "error" in parsed and parsed["error"] is not None:
            raise RuntimeError(f"MCP error: {parsed['error']}")
        return parsed["result"]


def call_tool(endpoint: str, request_id: int, name: str, arguments: dict):
    result = mcp_request(
        endpoint,
        request_id,
        "tools/call",
        {"name": name, "arguments": arguments},
    )
    structured = result.get("structuredContent")
    if structured is None:
        raise RuntimeError(f"Tool {name} missing structuredContent")
    return structured


def assert_true(condition: bool, message: str):
    if not condition:
        raise AssertionError(message)


def main() -> int:
    parser = argparse.ArgumentParser(description="MCP protocol contract test")
    parser.add_argument("--endpoint", default="http://127.0.0.1:44877/mcp")
    parser.add_argument("--project-path", default="src")
    args = parser.parse_args()

    request_id = 1
    print("[1/6] initialize")
    init = mcp_request(
        args.endpoint,
        request_id,
        "initialize",
        {
            "protocolVersion": "2025-11-25",
            "capabilities": {"resources": {"subscribe": True}, "tools": {}},
            "clientInfo": {"name": "mcp-protocol-contract-test", "version": "0.1.0"},
        },
    )
    request_id += 1
    assert_true("protocolVersion" in init, "initialize must return protocolVersion")

    print("[2/6] notifications/initialized")
    mcp_request(args.endpoint, request_id, "notifications/initialized", {})
    request_id += 1

    print("[3/6] openSession + capability assertions")
    open_session = call_tool(
        args.endpoint,
        request_id,
        "roblox.openSession",
        {"projectPath": args.project_path},
    )
    request_id += 1

    capabilities = open_session.get("sessionCapabilities")
    assert_true(capabilities is not None, "openSession must include sessionCapabilities")
    assert_true(
        capabilities.get("supportsStructuralOps") is False,
        "supportsStructuralOps must be false",
    )
    policy = capabilities.get("fileBackedMutationPolicy") or {}
    assert_true(policy.get("allowSetName") is False, "allowSetName must be false")
    allowed_props = policy.get("allowedSetProperty") or []
    assert_true("Source" in allowed_props, "allowedSetProperty must contain Source")

    session_id = str(open_session["sessionId"])
    root_id = str(open_session["rootInstanceId"])

    print("[4/6] readTree metadata assertions")
    tree = call_tool(
        args.endpoint,
        request_id,
        "roblox.readTree",
        {"sessionId": session_id, "instanceId": root_id},
    )
    request_id += 1

    assert_true(tree.get("sessionCapabilities") is not None, "readTree must include sessionCapabilities")
    file_backed_ids = tree.get("fileBackedInstanceIds") or []
    assert_true(len(file_backed_ids) > 0, "readTree must include fileBackedInstanceIds")

    print("[5/6] subscribeChanges metadata assertions")
    sub = call_tool(
        args.endpoint,
        request_id,
        "roblox.subscribeChanges",
        {"sessionId": session_id, "cursor": str(open_session.get("initialCursor", "0"))},
    )
    request_id += 1
    assert_true(sub.get("sessionCapabilities") is not None, "subscribeChanges must include sessionCapabilities")

    print("[6/6] closeSession")
    closed = call_tool(
        args.endpoint,
        request_id,
        "roblox.closeSession",
        {"sessionId": session_id},
    )
    assert_true(closed.get("closed") is True, "closeSession must report closed=true")

    print("Protocol contract test completed successfully.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
