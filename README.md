# Guestbook

Rack middleware that logs one [logfmt](https://brandur.org/logfmt) line per
request — Host header included, so it stays useful when one app serves many
virtual hosts. It resolves the real client IP from forwarding headers, but
only trusts a header when the request demonstrably arrived through the proxy
that sets it — so client-supplied headers from an untrusted peer can't forge
the logged IP; they're reported as `spoofed=…` and ignored.

```
at=info method=GET host=example.com path=/ status=200 bytes=2 duration=0.0004 ip=203.0.113.7
```

> Full usage, provider configuration and the security model are documented in
> later sections (added alongside the implementation).
