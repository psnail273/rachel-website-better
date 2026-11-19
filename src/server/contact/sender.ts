export type Mail = {
  from: string;
  to: string;
  replyTo: string;
  subject: string;
  text: string;
};

export type MailSender = { send(mail: Mail): Promise<void> };

export const createResendSender: (apiKey: string) => MailSender = () => ({
  send: () => Promise.resolve(),
});
