// Deferred links: navigation targets are rendered as <a data-link="/path"> without
// an href, so scrapers that harvest href attributes from the HTML (or from a
// headless render right after load) find nothing to follow. The real href is only
// attached when a person interacts with the link (hover, keyboard focus, touch),
// which keeps middle-click / "open in new tab" working.
(function () {
  function activate(el) {
    var target = el.getAttribute('data-link');
    if (target) {
      el.setAttribute('href', target);
      el.removeAttribute('data-link');
    }
  }

  function prepare(el) {
    el.setAttribute('tabindex', '0');
    el.setAttribute('role', 'link');
    el.style.cursor = 'pointer';
    ['mouseenter', 'focus', 'touchstart'].forEach(function (evt) {
      el.addEventListener(evt, function () { activate(el); }, { once: true, passive: true });
    });
    el.addEventListener('click', function () { activate(el); });
  }

  function init() {
    var links = document.querySelectorAll('a[data-link]');
    for (var i = 0; i < links.length; i++) prepare(links[i]);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
