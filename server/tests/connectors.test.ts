import type { ToolSet } from "ai";
import { describe, expect, it, vi } from "vitest";
import { createConnectorExecutionState, instrumentConnectorTools } from "../lib/connectors";
import type { GenerationSource } from "../lib/generationProtocol";

const GMAIL_TOOLKIT = {
  slug: "gmail",
  title: "Gmail",
  statusLine: "Checking your email…",
  doneLine: "Searched your email",
  emptyLine: "No matching emails",
  readTools: ["GMAIL_FETCH_EMAILS", "GMAIL_LIST_THREADS", "GMAIL_FETCH_MESSAGE_BY_THREAD_ID"],
} as const;

const CALENDAR_TOOLKIT = {
  slug: "googlecalendar",
  title: "Google Calendar",
  statusLine: "Checking your calendar…",
  doneLine: "Checked your calendar",
  emptyLine: "Nothing on your calendar matched",
  readTools: [
    "GOOGLECALENDAR_EVENTS_LIST",
    "GOOGLECALENDAR_FIND_EVENT",
    "GOOGLECALENDAR_FIND_FREE_SLOTS",
  ],
} as const;

describe("connector research tools", () => {
  it.each(["throws", "returns"] as const)(
    "latches a read that %s a failure and keeps concurrent calls safe",
    async (mode) => {
      const failure = {
        name: "ComposioToolExecutionError",
        cause: { status: 401, message: "Invalid API key: secret-value" },
      };
      const execute =
        mode === "throws"
          ? vi.fn().mockRejectedValue(failure)
          : vi.fn().mockResolvedValue({ successful: false, ...failure });
      const tools = {
        GMAIL_FETCH_EMAILS: { execute },
      } as unknown as ToolSet;
      const activities: { status: string }[] = [];
      const execution = createConnectorExecutionState();

      instrumentConnectorTools(
        tools,
        [GMAIL_TOOLKIT],
        { onActivity: (activity) => activities.push(activity) },
        execution,
      );

      const wrapped = tools.GMAIL_FETCH_EMAILS.execute as unknown as (
        args: unknown,
        options?: unknown,
      ) => Promise<unknown>;
      const [first, second] = await Promise.all([
        wrapped({}, { toolCallId: "gmail-1" }),
        wrapped({}, { toolCallId: "gmail-2" }),
      ]);

      expect(execute).toHaveBeenCalledTimes(1);
      expect(first).toMatchObject({
        successful: false,
        error: {
          code: "connector_service_auth",
          message: expect.stringContaining("Do not claim it was checked"),
        },
      });
      expect(second).toEqual(first);
      expect(JSON.stringify(first)).not.toContain("secret-value");
      expect(activities.map((activity) => activity.status)).toEqual(["started", "failed"]);
      expect(execution.disabledTools).toContain("GMAIL_FETCH_EMAILS");
      expect(execution.disabledTools).toContain("GMAIL_LIST_THREADS");
      expect(execution.inFlight.size).toBe(0);
    },
  );

  it("projects Gmail results into bounded evidence and actual email sources", async () => {
    const messages = Array.from({ length: 30 }, (_, index) => ({
      display_url:
        index < 15
          ? `https://mail.google.com/mail/u/0/#inbox/message-${index}`
          : "https://example.com/not-gmail",
      labelIds: ["INBOX", "IMPORTANT"],
      messageId: `message-${index}`,
      messageText: `Whitelisted message body ${index}. ${"b".repeat(3000)}`,
      messageTimestamp: "2026-07-13T09:30:00Z",
      preview: {
        body: index === 0 ? "The revised build is ready." : "x".repeat(6000),
        subject: `Preview ${index}`,
      },
      sender: `Sender ${index}`,
      subject: `Subject ${index}`,
      threadId: `thread-${index}`,
      to: `Recipient ${index} <recipient${index}@example.com>`,
      payload: { secret: "raw-payload" },
      attachments: [{ data: "attachment-data" }],
    }));
    const execute = vi.fn().mockResolvedValue({
      successful: true,
      data: { messages: [{}, 42, null, ...messages], raw: "raw-message" },
    });
    const tools = { GMAIL_FETCH_EMAILS: { execute } } as unknown as ToolSet;
    const sourceBatches: GenerationSource[][] = [];
    const activities: { status: string }[] = [];

    instrumentConnectorTools(
      tools,
      [GMAIL_TOOLKIT],
      {
        onActivity: (activity) => activities.push(activity),
        onSources: (sources) => sourceBatches.push(sources),
      },
      createConnectorExecutionState(),
    );

    const wrapped = tools.GMAIL_FETCH_EMAILS.execute as unknown as (
      args: unknown,
      options?: unknown,
    ) => Promise<unknown>;
    const result = await wrapped({
      max_results: 500,
      include_payload: true,
      query: "q".repeat(2000),
      label_ids: Array.from({ length: 40 }, (_, index) => String(index)),
    });

    expect(execute).toHaveBeenCalledWith(
      expect.objectContaining({
        max_results: 20,
        include_payload: true,
        query: "q".repeat(1000),
        label_ids: Array.from({ length: 20 }, (_, index) => String(index)),
      }),
      undefined,
    );
    const output = result as {
      data: { messages: { preview: { body: string } }[] };
    };
    expect(output.data.messages).toHaveLength(12);
    expect(output.data.messages[0].preview.body).toBe("The revised build is ready.");
    expect(output.data.messages[1].preview.body).toHaveLength(320);
    expect((output.data.messages[0] as { messageText?: string }).messageText).toHaveLength(1_200);
    expect(JSON.stringify([result, sourceBatches])).not.toMatch(
      /raw-payload|raw-message|attachment-data/,
    );
    expect(Buffer.byteLength(JSON.stringify(result), "utf8")).toBeLessThanOrEqual(24 * 1024);
    expect(sourceBatches).toHaveLength(1);
    expect(sourceBatches[0]).toHaveLength(12);
    expect(sourceBatches[0]?.[0]).toEqual({
      id: "https://mail.google.com/mail/u/0/#inbox/message-0",
      title: "Subject 0",
      url: "https://mail.google.com/mail/u/0/#inbox/message-0",
      domain: "mail.google.com",
      publishedAt: "2026-07-13T09:30:00Z",
      snippet: "Sender 0 · The revised build is ready.",
    });

    execute.mockResolvedValueOnce({
      successful: true,
      data: { messages: [{}, 42, null, { preview: {} }] },
    });
    const malformed = (await wrapped({ max_results: 1 })) as {
      data: { messages: unknown[] };
    };
    expect(malformed.data.messages).toEqual([]);
    expect(sourceBatches).toHaveLength(1);
    expect(activities.at(-1)?.status).toBe("empty");
  });

  it("projects Gmail thread listings and fetched messages through explicit allowlists", async () => {
    const listExecute = vi.fn().mockResolvedValue({
      successful: true,
      data: {
        threads: [
          {
            id: "thread-1",
            historyId: "history-1",
            snippet: "A safe thread preview",
            messages: [{ body: "must-not-pass" }],
            arbitrary: "must-not-pass",
          },
        ],
        nextPageToken: "next-token",
        resultSizeEstimate: 1,
        raw: "must-not-pass",
      },
    });
    const threadExecute = vi.fn().mockResolvedValue({
      successful: true,
      data: {
        threadId: "thread-1",
        historyId: "history-1",
        display_url: "https://mail.google.com/mail/u/0/#inbox/thread-1",
        messages: [
          {
            messageId: "message-1",
            threadId: "thread-1",
            sender: "Sender",
            to: "Reviewer <reviewer@example.com>",
            subject: "Build review",
            messageText: "The build is ready for review.",
            payload: { secret: "raw-payload" },
            attachments: [{ data: "attachment-data" }],
          },
        ],
      },
    });
    const tools = {
      GMAIL_LIST_THREADS: { execute: listExecute },
      GMAIL_FETCH_MESSAGE_BY_THREAD_ID: { execute: threadExecute },
    } as unknown as ToolSet;
    const sourceBatches: GenerationSource[][] = [];
    instrumentConnectorTools(
      tools,
      [GMAIL_TOOLKIT],
      { onSources: (sources) => sourceBatches.push(sources) },
      createConnectorExecutionState(),
    );

    const listResult = await (
      tools.GMAIL_LIST_THREADS.execute as unknown as (args: unknown) => Promise<unknown>
    )({ max_results: 50, verbose: true });
    const threadResult = await (
      tools.GMAIL_FETCH_MESSAGE_BY_THREAD_ID.execute as unknown as (
        args: unknown,
      ) => Promise<unknown>
    )({ thread_id: "thread-1" });

    expect(listExecute).toHaveBeenCalledWith({ max_results: 20, verbose: false }, undefined);
    expect(listResult).toEqual({
      successful: true,
      data: {
        threads: [
          {
            id: "thread-1",
            historyId: "history-1",
            snippet: "A safe thread preview",
          },
        ],
        nextPageToken: "next-token",
        resultSizeEstimate: 1,
      },
    });
    expect(threadResult).toMatchObject({
      successful: true,
      data: {
        threadId: "thread-1",
        messages: [
          {
            sender: "Sender",
            subject: "Build review",
            messageText: "The build is ready for review.",
            to: "Reviewer <reviewer@example.com>",
          },
        ],
      },
    });
    expect(JSON.stringify([listResult, threadResult, sourceBatches])).not.toMatch(
      /must-not-pass|raw-payload|attachment-data/,
    );
    expect(sourceBatches).toEqual([
      [
        expect.objectContaining({
          id: "https://mail.google.com/mail/u/0/#inbox/thread-1",
          title: "Build review",
          domain: "mail.google.com",
        }),
      ],
    ]);
  });

  it("strips attachment and raw flags and bounds strings at every argument depth", async () => {
    const execute = vi.fn().mockResolvedValue({ successful: true, data: {} });
    const tools = { GMAIL_FETCH_EMAILS: { execute } } as unknown as ToolSet;
    instrumentConnectorTools(tools, [GMAIL_TOOLKIT], {}, createConnectorExecutionState());
    const executeTool = tools.GMAIL_FETCH_EMAILS.execute as unknown as (
      args: unknown,
      options?: unknown,
    ) => Promise<unknown>;

    await executeTool(
      {
        query: "x".repeat(5000),
        options: {
          include_attachments: true,
          raw_payload: "secret",
          filter: { label: "y".repeat(5000), attachmentIds: ["a"], deeper: { tooDeep: { x: 1 } } },
        },
        ids: [{ attachment_id: "a", id: "1" }, ["nested"]],
      },
      { toolCallId: "nested-args" },
    );

    expect(execute.mock.calls[0]![0]).toEqual({
      query: "x".repeat(1000),
      options: {
        include_attachments: false,
        filter: { label: "y".repeat(1000), deeper: {} },
      },
      ids: [{ id: "1" }],
    });
  });

  it("passes calendar events to the model only through the allowlisted projection", async () => {
    const event = {
      kind: "calendar#event",
      etag: '"3381"',
      id: "event-1",
      status: "confirmed",
      htmlLink: "https://www.google.com/calendar/event?eid=abc",
      summary: "Design review",
      description: "Agenda: hero states",
      location: "Room 4",
      creator: { email: "assistant@example.com" },
      organizer: { email: "lead@example.com", displayName: "Lead" },
      start: { dateTime: "2026-10-26T10:00:00-04:00", timeZone: "America/New_York" },
      end: { dateTime: "2026-10-26T11:00:00-04:00", timeZone: "America/New_York" },
      iCalUID: "uid@google.com",
      hangoutLink: "https://meet.google.com/abc-defg-hij",
      conferenceData: { entryPoints: [{ uri: "tel:+1-555-0100", pin: "123456" }] },
      extendedProperties: { private: { crmToken: "secret-token" } },
      attendees: [
        { email: "me@example.com", self: true, responseStatus: "accepted", comment: "late" },
      ],
      reminders: { useDefault: true },
    };
    const execute = vi.fn().mockResolvedValue({
      successful: true,
      data: { kind: "calendar#events", nextSyncToken: "sync-token", items: [event] },
    });
    const tools = { GOOGLECALENDAR_EVENTS_LIST: { execute } } as unknown as ToolSet;
    instrumentConnectorTools(tools, [CALENDAR_TOOLKIT], {}, createConnectorExecutionState());
    const executeTool = tools.GOOGLECALENDAR_EVENTS_LIST.execute as unknown as (
      args: unknown,
      options?: unknown,
    ) => Promise<unknown>;

    expect(await executeTool({}, { toolCallId: "calendar" })).toEqual({
      successful: true,
      data: {
        events: [
          {
            id: "event-1",
            summary: "Design review",
            status: "confirmed",
            start: { dateTime: "2026-10-26T10:00:00-04:00", timeZone: "America/New_York" },
            end: { dateTime: "2026-10-26T11:00:00-04:00", timeZone: "America/New_York" },
            location: "Room 4",
            description: "Agenda: hero states",
            organizer: "Lead <lead@example.com>",
            attendees: ["me@example.com, accepted, you"],
            htmlLink: "https://www.google.com/calendar/event?eid=abc",
          },
        ],
      },
    });
  });

  it("passes free and busy times without event details", async () => {
    const execute = vi.fn().mockResolvedValue({
      successful: true,
      data: {
        calendars: {
          primary: {
            busy: [{ start: "2026-10-26T10:00:00Z", end: "2026-10-26T11:00:00Z", id: "x" }],
          },
        },
        token: "secret",
      },
    });
    const tools = { GOOGLECALENDAR_FIND_FREE_SLOTS: { execute } } as unknown as ToolSet;
    instrumentConnectorTools(tools, [CALENDAR_TOOLKIT], {}, createConnectorExecutionState());
    const executeTool = tools.GOOGLECALENDAR_FIND_FREE_SLOTS.execute as unknown as (
      args: unknown,
      options?: unknown,
    ) => Promise<unknown>;

    expect(await executeTool({}, { toolCallId: "slots" })).toEqual({
      successful: true,
      data: { busy: [{ start: "2026-10-26T10:00:00Z", end: "2026-10-26T11:00:00Z" }] },
    });
  });

  it("hard-caps a connector's serialized result size", async () => {
    const execute = vi.fn().mockResolvedValue({
      successful: true,
      data: {
        items: Array.from({ length: 50 }, (_, index) => ({
          id: `event-${index}`,
          summary: "s".repeat(240),
          description: '\\"\n'.repeat(400),
          location: "l".repeat(240),
          start: { dateTime: "2026-10-26T10:00:00Z" },
        })),
      },
    });
    const tools = { GOOGLECALENDAR_EVENTS_LIST: { execute } } as unknown as ToolSet;

    instrumentConnectorTools(tools, [CALENDAR_TOOLKIT], {}, createConnectorExecutionState());

    const executeTool = tools.GOOGLECALENDAR_EVENTS_LIST.execute as unknown as (
      args: unknown,
      options?: unknown,
    ) => Promise<unknown>;
    const result = await executeTool({}, { toolCallId: "large-result" });
    expect(result).toMatchObject({ successful: true, truncated: true });
    expect(Buffer.byteLength(JSON.stringify(result), "utf8")).toBeLessThanOrEqual(24 * 1024);
  });

  it.each([true, false])(
    "handles cancellation with an already-aborted signal=%s",
    async (alreadyAborted) => {
      const controller = new AbortController();
      const execute = vi.fn(() => new Promise<never>(() => {}));
      const tools = { GMAIL_FETCH_EMAILS: { execute } } as unknown as ToolSet;
      const execution = createConnectorExecutionState();
      const activities: { status: string }[] = [];
      instrumentConnectorTools(
        tools,
        [GMAIL_TOOLKIT],
        {
          onActivity: (activity) => activities.push(activity),
        },
        execution,
      );
      if (alreadyAborted) controller.abort();
      const pending = (
        tools.GMAIL_FETCH_EMAILS.execute as unknown as (
          args: unknown,
          options: { abortSignal: AbortSignal },
        ) => Promise<unknown>
      )({}, { abortSignal: controller.signal });
      if (!alreadyAborted) {
        await Promise.resolve();
        controller.abort();
      }
      await expect(pending).resolves.toMatchObject({
        successful: false,
        error: { code: "connector_timeout" },
      });
      expect(execute).toHaveBeenCalledTimes(alreadyAborted ? 0 : 1);
      expect(activities.map(({ status }) => status)).toEqual(["started", "failed"]);
      expect(execution.disabledTools).toContain("GMAIL_FETCH_EMAILS");
      expect(execution.inFlight.size).toBe(0);
    },
  );

  it("returns a safe timeout without waiting for a stuck provider call", async () => {
    vi.useFakeTimers();
    try {
      const execute = vi.fn(() => new Promise<never>(() => {}));
      const tools = { GOOGLECALENDAR_EVENTS_LIST: { execute } } as unknown as ToolSet;
      const execution = createConnectorExecutionState();
      instrumentConnectorTools(tools, [CALENDAR_TOOLKIT], {}, execution);

      const executeTool = tools.GOOGLECALENDAR_EVENTS_LIST.execute as unknown as (
        args: unknown,
        options?: unknown,
      ) => Promise<unknown>;
      const pending = executeTool({}, { toolCallId: "calendar-timeout" });
      await vi.advanceTimersByTimeAsync(10_000);
      await expect(pending).resolves.toMatchObject({
        successful: false,
        error: { code: "connector_timeout" },
      });
      expect(execution.disabledTools).toContain("GOOGLECALENDAR_EVENTS_LIST");
    } finally {
      vi.useRealTimers();
    }
  });
});
