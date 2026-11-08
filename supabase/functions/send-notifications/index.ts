import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const mailtrapToken = Deno.env.get("MAILTRAP_API_TOKEN")!;
const fromEmail = Deno.env.get("MAILTRAP_FROM_EMAIL")!;
const fromName = Deno.env.get("MAILTRAP_FROM_NAME") ?? "Roomly";
const appUrl = Deno.env.get("ROOMLY_APP_URL") ?? "http://localhost:3000";

function bookingTime(value: string, timezone: string) {
  return new Intl.DateTimeFormat("en-CA", {
    dateStyle: "full",
    timeStyle: "short",
    timeZone: timezone,
  }).format(new Date(value));
}

function subjectFor(eventType: string, payload: Record<string, unknown>) {
  const organization = payload.organization_name ?? "Roomly";

  switch (eventType) {
    case "membership_request_submitted":
      return `New membership request · ${organization}`;
    case "membership_request_approved":
      return `Your ${organization} membership was approved`;
    case "membership_request_rejected":
      return `Your ${organization} membership request was not approved`;
    case "booking_requested":
      return `Booking request received · ${organization}`;
    case "booking_approved":
      return `Booking confirmed · ${organization}`;
    case "booking_declined":
      return `Booking request declined · ${organization}`;
    case "booking_cancelled":
      return `Booking cancelled · ${organization}`;
    case "booking_updated":
      return `Booking updated · ${organization}`;
    case "booking_reminder":
      return `Upcoming booking reminder · ${organization}`;
    default:
      return `Roomly update · ${organization}`;
  }
}

function bodyFor(eventType: string, payload: Record<string, unknown>) {
  const organization = payload.organization_name ?? "Roomly";
  const room = payload.room_name ?? "your reserved room";
  const title = payload.booking_title ?? "Your booking";
  const startsAt = payload.starts_at as string | undefined;
  const endsAt = payload.ends_at as string | undefined;
  const timezone = (payload.timezone as string | undefined) ?? "America/Edmonton";

  const schedule = startsAt && endsAt
    ? `<p><strong>${bookingTime(startsAt, timezone)}</strong> to <strong>${bookingTime(endsAt, timezone)}</strong></p>`
    : "";

  switch (eventType) {
    case "membership_request_submitted":
      return `
        <p>A new membership request was submitted for <strong>${organization}</strong>.</p>
        <p><strong>Name:</strong> ${payload.applicant_name ?? "Not provided"}</p>
        <p><strong>Email:</strong> ${payload.applicant_email ?? ""}</p>
        <p>Open <strong>Manage members → Pending requests</strong> to review it.</p>
      `;

    case "membership_request_approved":
      return `
        <p>Your membership request for <strong>${organization}</strong> was approved.</p>
        <p>You can now sign in and book available rooms.</p>
        <p><a href="${appUrl}">Open Roomly</a></p>
      `;

    case "membership_request_rejected":
      return `
        <p>Your membership request for <strong>${organization}</strong> was not approved.</p>
        ${payload.review_note ? `<p><strong>Note:</strong> ${payload.review_note}</p>` : ""}
        <p>You may submit a new request later if circumstances change.</p>
      `;

    case "booking_requested":
      return `
        <p>Your booking request for <strong>${title}</strong> was received.</p>
        <p><strong>Room:</strong> ${room}</p>
        ${schedule}
        <p>The organization administrator will review the request.</p>
      `;

    case "booking_approved":
      return `
        <p>Your booking for <strong>${title}</strong> is confirmed.</p>
        <p><strong>Room:</strong> ${room}</p>
        ${schedule}
      `;

    case "booking_declined":
      return `
        <p>Your booking request for <strong>${title}</strong> was declined.</p>
        <p><strong>Room:</strong> ${room}</p>
        ${schedule}
      `;

    case "booking_cancelled":
      return `
        <p>Your booking for <strong>${title}</strong> was cancelled.</p>
        <p><strong>Room:</strong> ${room}</p>
        ${schedule}
      `;

    case "booking_updated":
      return `
        <p>Your booking for <strong>${title}</strong> was updated.</p>
        <p><strong>Room:</strong> ${room}</p>
        ${schedule}
      `;

    case "booking_reminder":
      return `
        <p>This is a reminder for your upcoming booking.</p>
        <p><strong>${title}</strong></p>
        <p><strong>Room:</strong> ${room}</p>
        ${schedule}
      `;

    default:
      return `<p>You have a Roomly update for ${organization}.</p>`;
  }
}

async function sendEmail(
  to: string,
  eventType: string,
  payload: Record<string, unknown>,
) {
  const response = await fetch("https://send.api.mailtrap.io/api/send", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${mailtrapToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: {
        email: fromEmail,
        name: fromName,
      },
      to: [{ email: to }],
      subject: subjectFor(eventType, payload),
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px;">
          <h2>Roomly</h2>
          ${bodyFor(eventType, payload)}
        </div>
      `,
      category: eventType,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Mailtrap request failed: ${response.status} ${detail}`);
  }
}

const { data: queued, error: queueError } = await supabase
  .from("rm_notification_queue")
  .select("*")
  .eq("status", "queued")
  .order("created_at")
  .limit(25);

if (queueError) {
  return new Response(JSON.stringify({ error: queueError.message }), {
    status: 500,
  });
}

let sent = 0;
let failed = 0;

for (const notification of queued ?? []) {
  try {
    await sendEmail(
      notification.recipient_email,
      notification.event_type,
      notification.payload ?? {},
    );

    await supabase
      .from("rm_notification_queue")
      .update({
        status: "sent",
        sent_at: new Date().toISOString(),
        last_error: null,
      })
      .eq("id", notification.id);

    sent += 1;
  } catch (error) {
    await supabase
      .from("rm_notification_queue")
      .update({
        status: "failed",
        attempts: (notification.attempts ?? 0) + 1,
        last_error: error instanceof Error ? error.message : String(error),
      })
      .eq("id", notification.id);

    failed += 1;
  }
}

return new Response(
  JSON.stringify({ queued: queued?.length ?? 0, sent, failed }),
  { headers: { "Content-Type": "application/json" } },
);