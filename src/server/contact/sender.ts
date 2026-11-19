import { Resend } from "resend";

export type Mail = {
  from: string;
  to: string;
  replyTo: string;
  subject: string;
  text: string;
};

export type MailSender = { send(mail: Mail): Promise<void> };

export function createResendSender(apiKey: string): MailSender {
  return {
    async send(mail) {
      const { error } = await new Resend(apiKey).emails.send(mail);
      if (error !== null) throw new Error(error.message);
    },
  };
}
