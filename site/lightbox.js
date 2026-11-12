// Screenshot lightbox: each .gallery link opens its full image over the page. Without JS the links open the image.
(() => {
	const links = [...document.querySelectorAll('.gallery a.shot')];
	if (!links.length) return;

	const box = document.createElement('div');
	box.className = 'lightbox';
	box.hidden = true;
	box.setAttribute('role', 'dialog');
	box.setAttribute('aria-modal', 'true');
	box.setAttribute('aria-label', 'Screenshot viewer');
	box.innerHTML = `
		<figure class="lb-stage">
			<img class="lb-image" alt="">
			<figcaption><span class="lb-caption"></span> <span class="lb-count" aria-live="polite"></span></figcaption>
		</figure>
		<button class="lb-btn lb-prev" type="button" aria-label="Previous screenshot">‹</button>
		<button class="lb-btn lb-next" type="button" aria-label="Next screenshot">›</button>
		<button class="lb-btn lb-close" type="button" aria-label="Close">×</button>`;
	document.body.append(box);

	const image = box.querySelector('.lb-image');
	const caption = box.querySelector('.lb-caption');
	const count = box.querySelector('.lb-count');
	const buttons = [...box.querySelectorAll('button')];
	const outside = [...document.body.children].filter((el) => el !== box && el.tagName !== 'SCRIPT');
	let index = 0;
	let opener = null;

	const show = (next) => {
		index = (next + links.length) % links.length;
		const link = links[index];
		const thumb = link.querySelector('img');
		image.classList.remove('is-loaded');
		image.onload = () => image.classList.add('is-loaded');
		image.src = link.href;
		image.alt = thumb.alt;
		caption.textContent = link.closest('figure').querySelector('figcaption').textContent;
		count.textContent = `${index + 1} / ${links.length}`;
		// Warm the neighbours so prev/next feel instant.
		for (const step of [1, -1]) new Image().src = links[(index + step + links.length) % links.length].href;
	};

	const open = (i, from) => {
		opener = from;
		show(i);
		box.hidden = false;
		document.documentElement.classList.add('lb-open');
		outside.forEach((el) => (el.inert = true));
		// Reading a layout value commits the hidden state, so the fade-in runs without waiting for a frame callback.
		void box.offsetWidth;
		box.classList.add('is-open');
		box.querySelector('.lb-close').focus();
	};

	const close = () => {
		box.classList.remove('is-open');
		box.hidden = true;
		document.documentElement.classList.remove('lb-open');
		outside.forEach((el) => (el.inert = false));
		image.removeAttribute('src');
		opener?.focus();
	};

	links.forEach((link, i) => link.addEventListener('click', (event) => {
		if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
		event.preventDefault();
		open(i, link);
	}));

	box.querySelector('.lb-prev').addEventListener('click', () => show(index - 1));
	box.querySelector('.lb-next').addEventListener('click', () => show(index + 1));
	box.querySelector('.lb-close').addEventListener('click', close);
	// The backdrop is the box itself and the stage's empty margin; the image and buttons don't close it.
	box.addEventListener('click', (event) => { if (event.target === box || event.target.classList.contains('lb-stage')) close(); });

	box.addEventListener('keydown', (event) => {
		if (event.key === 'Escape') return close();
		if (event.key === 'ArrowLeft') return show(index - 1);
		if (event.key === 'ArrowRight') return show(index + 1);
		if (event.key !== 'Tab') return;

		// inert already blocks the page; this keeps Tab cycling inside the buttons instead of leaving for the browser bar.
		const first = buttons[0];
		const last = buttons[buttons.length - 1];
		if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
		else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
	});

	let touchX = null;
	let touchY = null;
	box.addEventListener('touchstart', (event) => { [touchX, touchY] = [event.touches[0].clientX, event.touches[0].clientY]; }, { passive: true });
	box.addEventListener('touchend', (event) => {
		if (touchX === null) return;
		const dx = event.changedTouches[0].clientX - touchX;
		const dy = event.changedTouches[0].clientY - touchY;
		touchX = null;
		if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) show(index + (dx < 0 ? 1 : -1));
	});
})();
