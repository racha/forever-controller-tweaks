// Sticky top bar: its height for anchor offsets, a border once the page scrolls, and the current section's link.
(() => {
	const bar = document.querySelector('.top');
	const nav = bar?.querySelector('nav');
	if (!nav) return;

	const root = document.documentElement;
	const setHeight = () => root.style.setProperty('--bar-h', `${bar.offsetHeight}px`);
	setHeight();
	if ('ResizeObserver' in window) new ResizeObserver(setHeight).observe(bar);

	const onScroll = () => bar.classList.toggle('is-scrolled', scrollY > 4);
	onScroll();
	addEventListener('scroll', onScroll, { passive: true });

	const links = new Map();
	for (const link of nav.querySelectorAll('a[href^="#"]')) {
		const section = document.getElementById(link.hash.slice(1));
		if (section) links.set(section, link);
	}
	if (!links.size || !('IntersectionObserver' in window)) return;

	// Keep the current link visible when the nav scrolls sideways on a phone, without moving the page.
	const reveal = (link) => {
		const { left, right } = link.getBoundingClientRect();
		const box = nav.getBoundingClientRect();
		if (left < box.left) nav.scrollLeft -= box.left - left + 12;
		else if (right > box.right) nav.scrollLeft += right - box.right + 24;
	};

	let current = null;
	const setCurrent = (link) => {
		if (link === current) return;
		current?.removeAttribute('aria-current');
		current = link;
		if (!link) return;
		link.setAttribute('aria-current', 'true');
		reveal(link);
	};

	// A section is current while it crosses a thin band a little below the bar.
	const visible = new Set();
	const observer = new IntersectionObserver((entries) => {
		for (const { isIntersecting, target } of entries) isIntersecting ? visible.add(target) : visible.delete(target);
		const first = [...links.keys()].find((section) => visible.has(section));
		setCurrent(first ? links.get(first) : null);
	}, { rootMargin: '-30% 0px -60% 0px' });

	links.forEach((_, section) => observer.observe(section));
})();
