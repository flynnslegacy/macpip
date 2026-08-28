<?php
declare(strict_types=1);

$recipient = 'david@markowicz.fr';
$maxNameLength = 100;
$maxEmailLength = 150;
$maxMessageLength = 5000;

$wantsJson = (
    ($_SERVER['HTTP_X_REQUESTED_WITH'] ?? '') === 'XMLHttpRequest'
    || strpos($_SERVER['HTTP_ACCEPT'] ?? '', 'application/json') !== false
);

function respond(bool $wantsJson, bool $success, string $code, ?string $redirectBase = null): void
{
    if ($wantsJson) {
        header('Content-Type: application/json; charset=utf-8');
        http_response_code($success ? 200 : 422);
        echo json_encode(['success' => $success, 'code' => $code]);
        exit;
    }

    $base = $redirectBase ?? 'index.html';
    $query = http_build_query(['sent' => $success ? '1' : '0', 'code' => $code]);
    header('Location: ' . $base . '?' . $query . '#contact');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Method Not Allowed';
    exit;
}

// Honeypot: bots fill hidden fields, humans never see them.
if (!empty($_POST['website'])) {
    respond($wantsJson, true, 'ok');
}

$name = trim((string) ($_POST['name'] ?? ''));
$email = trim((string) ($_POST['email'] ?? ''));
$message = trim((string) ($_POST['message'] ?? ''));

$stripNewlines = static fn (string $value): string => trim(preg_replace('/[\r\n]+/', ' ', $value) ?? '');

$name = $stripNewlines($name);
$email = $stripNewlines($email);

if ($name === '' || mb_strlen($name) > $maxNameLength) {
    respond($wantsJson, false, 'invalid_name');
}
if (!filter_var($email, FILTER_VALIDATE_EMAIL) || mb_strlen($email) > $maxEmailLength) {
    respond($wantsJson, false, 'invalid_email');
}
if ($message === '' || mb_strlen($message) > $maxMessageLength) {
    respond($wantsJson, false, 'invalid_message');
}

$host = preg_replace('/[^a-zA-Z0-9.\-]/', '', (string) ($_SERVER['HTTP_HOST'] ?? 'anypip.exemples.xyz'));
$fromAddress = 'no-reply@' . $host;

$subject = 'AnyPiP - Nouveau message de ' . $name;

$body = "Nouveau message depuis le formulaire de contact AnyPiP.\n\n";
$body .= "Nom : {$name}\n";
$body .= "Email : {$email}\n\n";
$body .= "Message :\n{$message}\n";

$headers = [
    'From: AnyPiP Website <' . $fromAddress . '>',
    'Reply-To: ' . $name . ' <' . $email . '>',
    'Content-Type: text/plain; charset=UTF-8',
];

$sent = mail($recipient, $subject, $body, implode("\r\n", $headers));

respond($wantsJson, $sent, $sent ? 'ok' : 'send_failed');
