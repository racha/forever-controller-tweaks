// Fade sections and cards in as they scroll into view. Transform and opacity only, so nothing shifts the layout.
// The .js class (set in <head>) hides them first; without JS, or with reduced motion, everything just shows.
(() => {
	const items = document.querySelectorAll('.reveal');
	const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
	if (reduced || !('IntersectionObserver' in window)) return items.forEach((el) => el.classList.add('is-visible'));

	const observer = new IntersectionObserver((entries) => {
		for (const { isIntersecting, target } of entries) {
			if (!isIntersecting) continue;
			target.classList.add('is-visible');
			observer.unobserve(target);
		}
	}, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

	items.forEach((el) => observer.observe(el));
})();
