"""Отправка уведомлений."""

import logging
import smtplib
from dataclasses import dataclass
from email.message import EmailMessage
from urllib.parse import urlparse

from depot.domain.errors import NotificationError

log = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class SentMessage:
    recipient: str
    subject: str
    body: str


class SmtpNotifier:
    def __init__(self, smtp_url: str, sender: str = "no-reply@depot.example") -> None:
        self._url = urlparse(smtp_url)
        self._sender = sender

    def send(self, recipient: str, subject: str, body: str) -> None:
        message = EmailMessage()
        message["From"] = self._sender
        message["To"] = recipient
        message["Subject"] = subject
        message.set_content(body)

        try:
            with smtplib.SMTP(
                self._url.hostname or "localhost", self._url.port or 25, timeout=10
            ) as smtp:
                if self._url.username:
                    smtp.starttls()
                    smtp.login(self._url.username, self._url.password or "")
                smtp.send_message(message)
        except (smtplib.SMTPException, OSError) as exc:
            raise NotificationError("сервис уведомлений недоступен") from exc


class LoggingNotifier:
    """Пишет в журнал вместо отправки — для локального запуска."""

    def send(self, recipient: str, subject: str, body: str) -> None:
        log.info(
            "notification: %s",
            subject,
            extra={"recipient": recipient, "body_length": len(body)},
        )


class MemoryNotifier:
    """Записывает вызовы: тест проверяет, что именно было отправлено."""

    def __init__(self) -> None:
        self.sent: list[SentMessage] = []
        self.fail = False

    def send(self, recipient: str, subject: str, body: str) -> None:
        if self.fail:
            raise NotificationError("сервис уведомлений недоступен")
        self.sent.append(SentMessage(recipient=recipient, subject=subject, body=body))

    def clear(self) -> None:
        self.sent.clear()
