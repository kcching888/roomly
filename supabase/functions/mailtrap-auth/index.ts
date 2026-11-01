import { Webhook } from "npm:standardwebhooks@1.0.0";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

const fail = (message: string, status: number) =>
  json(
    {
      error: {
        http_code: status,
        message,
      },
    },
    status,
  );

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return fail("Method not allowed.", 405);
  }

  const apiToken = Deno.env.get("MAILTRAP_API_TOKEN");
  const signingSecret = Deno.env.get("SEND_EMAIL_HOOK_SECRET");

  // SUPABASE_URL is supplied automatically to Edge Functions.
  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  const appUrl = Deno.env.get("APP_URL");
  const fromEmail = Deno.env.get("MAILTRAP_FROM_EMAIL");
  const fromName = Deno.env.get("MAILTRAP_FROM_NAME") ?? "Roomly";
  const allowedRecipient = Deno.env.get("MAILTRAP_TEST_RECIPIENT");

  if (
    !apiToken ||
    !signingSecret ||
    !supabaseUrl ||
    !appUrl ||
    !fromEmail ||
    !allowedRecipient
  ) {
    console.error("Mailtrap authentication email configuration is incomplete.");
    return fail("Email service is not configured.", 500);
  }

  // This endpoint accepts only verified Supabase webhook requests.
  const rawBody = await req.text();
  let payload: any;

  try {
    const secret = signingSecret.replace(/^v1,whsec_/, "");

    const webhook = new Webhook(secret);

    payload = webhook.verify(
      rawBody,
      Object.fromEntries(req.headers.entries()),
    );
  } catch {
    return fail("Invalid webhook signature.", 401);
  }

  const email = payload?.user?.email;
  const action = payload?.email_data?.email_action_type;
  const tokenHash = payload?.email_data?.token_hash;

  if (
    typeof email !== "string" ||
    typeof tokenHash !== "string" ||
    tokenHash.length === 0
  ) {
    return fail("Invalid authentication email request.", 400);
  }

  // The existing Roomly app currently implements signup only.
  // Reject unsupported actions rather than sending incorrect links.
  if (action !== "signup") {
    return fail(
      "This development email integration supports signup confirmation only.",
      422,
    );
  }

  // Prevent this demo-domain integration from sending to arbitrary addresses.
  if (
    email.trim().toLowerCase() !==
      allowedRecipient.trim().toLowerCase()
  ) {
    return fail(
      "This development setup can email only its configured test recipient.",
      403,
    );
  }

  let confirmationUrl: URL;

  try {
    const redirect = new URL(appUrl);

    const isLocal = [
      "localhost",
      "127.0.0.1",
      "[::1]",
    ].includes(redirect.hostname);

    if (
      redirect.protocol !== "https:" &&
      !(redirect.protocol === "http:" && isLocal)
    ) {
      throw new Error("Invalid application URL.");
    }

    confirmationUrl = new URL(
      "/auth/v1/verify",
      supabaseUrl,
    );

    confirmationUrl.searchParams.set("token", tokenHash);
    confirmationUrl.searchParams.set("type", "signup");

    // Use the configured application URL, not a caller-supplied redirect.
    confirmationUrl.searchParams.set(
      "redirect_to",
      redirect.toString(),
    );
  } catch {
    console.error("Invalid authentication redirect configuration.");
    return fail("Email service is not configured correctly.", 500);
  }

  try {
    const response = await fetch(
      "https://send.api.mailtrap.io/api/send",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: {
            email: fromEmail,
            name: fromName,
          },
          to: [
            {
              email,
            },
          ],
          subject: "Confirm your Roomly account",
          text: [
            "Welcome to Roomly.",
            "",
            "Confirm your email address using this link:",
            confirmationUrl.toString(),
            "",
            "If you did not request this account, ignore this email.",
          ].join("\n"),
          category: "Authentication",
        }),

        // Keep the external request short enough for an Auth hook.
        signal: AbortSignal.timeout(3500),
      },
    );

    if (!response.ok) {
      // Never log the API token, webhook payload, or confirmation link.
      console.error(
        `Mailtrap rejected the email request: HTTP ${response.status}`,
      );

      return fail(
        "The confirmation email could not be sent.",
        502,
      );
    }

    // Provider acceptance does not guarantee inbox delivery.
    return json({});
  } catch {
    console.error("Mailtrap request failed or timed out.");

    return fail(
      "The email service is temporarily unavailable.",
      502,
    );
  }
});