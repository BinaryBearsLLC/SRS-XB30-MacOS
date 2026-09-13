// Embedded BinaryBears lab navigation. Standalone project behavior is unchanged.
(() => {
  if (window.parent === window) return;
  const trustedParent = (origin) => {
    if (origin === 'https://binarybears.com' || origin === 'https://www.binarybears.com') return true;
    // Local review is allowed only when the project is also served locally.
    const localHosts = ['localhost', '127.0.0.1', '[::1]'];
    try {
      const url = new URL(origin);
      return localHosts.includes(location.hostname) && localHosts.includes(url.hostname) && url.protocol === 'http:';
    } catch { return false; }
  };
  let token = null;
  let parentOrigin = null;
  let activeLink = null;
  window.addEventListener('message', (event) => {
    if (event.source !== window.parent || !trustedParent(event.origin)) return;
    const message = event.data;
    if (!message || typeof message.token !== 'string') return;
    if (message.type === 'bb-preview:connect' && /^[\da-f-]{36}$/i.test(message.token)) {
      token = message.token;
      parentOrigin = event.origin;
      window.parent.postMessage({ type: 'bb-preview:ready', token }, parentOrigin);
    } else if (message.type === 'bb-preview:display' && message.token === token) {
      // Wait for the revealed frame to paint before accepting user navigation.
      const displayedToken = token;
      requestAnimationFrame(() => requestAnimationFrame(() => {
        window.parent.postMessage({ type: 'bb-preview:active', token: displayedToken }, parentOrigin);
      }));
    } else if (message.type === 'bb-preview:resume' && message.token === token) {
      activeLink?.focus({ preventScroll: true });
    }
  });
  const intercept = (event) => {
    if (!token || (event.type === 'auxclick' && event.button !== 1)) return;
    const link = event.target instanceof Element ? event.target.closest('a[href]') : null;
    if (!link) return;
    const url = new URL(link.href, location.href);
    // In-page navigation and interactive controls keep their normal behavior.
    if (url.origin === location.origin && url.pathname === location.pathname &&
        url.search === location.search && url.hash && !link.hasAttribute('download')) return;
    if (!['https:', 'http:', 'mailto:', 'tel:'].includes(url.protocol)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    activeLink = link;
    // The parent chooses its configured project URL; never accept a supplied URL.
    window.parent.postMessage({ type: 'bb-preview:visit', token }, parentOrigin);
  };
  document.addEventListener('click', intercept, true);
  document.addEventListener('auxclick', intercept, true);
})();
