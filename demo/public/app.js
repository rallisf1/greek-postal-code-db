const $ = (selector) => document.querySelector(selector);
const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character]);
async function request(path, options) {
  const response = await fetch(path, options);
  const body = await response.json();
  if (!response.ok) throw new Error(body.error ?? 'Request failed');
  return body;
}
function range(start, end) { return start || end ? `${start ?? ''} – ${end ?? ''}` : 'Not recorded'; }

$('#postcode-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const error = $('#postcode-error'), value = $('#postcode').value;
  error.hidden = true;
  try {
    const result = await request(`/api/postcodes/${encodeURIComponent(value)}`);
    const hierarchy = result.hierarchy;
    $('#hierarchy').innerHTML = [
      ['Municipal unit', hierarchy.municipalUnit?.name], ['Community', hierarchy.community?.name], ['Municipality', hierarchy.municipality?.name],
      ['Regional unit', hierarchy.regionalUnit?.name], ['Region', hierarchy.region?.name], ['Decentralized administration', hierarchy.decentralizedAdministration?.name]
    ].filter(([, value]) => value).map(([label, value]) => `<dt>${label}</dt><dd>${escapeHtml(value)}</dd>`).join('');
    $('#streets').innerHTML = result.streets.map((street) => `<tr><td>${escapeHtml(street.name)}</td><td>${escapeHtml(range(street.oddStart, street.oddEnd))}</td><td>${escapeHtml(range(street.evenStart, street.evenEnd))}</td></tr>`).join('');
    $('#postcode-result').hidden = false;
  } catch (cause) { error.textContent = cause.message; error.hidden = false; $('#postcode-result').hidden = true; }
});

async function loadRegions() {
  const regions = await request('/api/regions');
  $('#region').insertAdjacentHTML('beforeend', regions.map((region) => `<option value="${region.id}">${escapeHtml(region.name)}</option>`).join(''));
}
$('#region').addEventListener('change', async (event) => {
  const select = $('#regional-unit');
  select.innerHTML = '<option value="">Select a regional unit</option>'; select.disabled = !event.target.value;
  if (!event.target.value) return;
  const units = await request(`/api/regional-units?regionId=${encodeURIComponent(event.target.value)}`);
  select.insertAdjacentHTML('beforeend', units.map((unit) => `<option value="${unit.id}">${escapeHtml(unit.name)}</option>`).join(''));
});
loadRegions().catch((cause) => console.error(cause));

let searchTimer;
$('#municipality-search').addEventListener('input', (event) => {
  clearTimeout(searchTimer);
  const list = $('#municipality-results'), query = event.target.value;
  if (!query.trim()) { list.hidden = true; return; }
  searchTimer = setTimeout(async () => {
    try {
      const results = await request(`/api/municipalities/search?q=${encodeURIComponent(query)}&limit=10`);
      list.innerHTML = results.map((item) => `<li><button type="button" data-name="${escapeHtml(item.name)}">${escapeHtml(item.name)}</button></li>`).join('');
      list.hidden = results.length === 0;
    } catch { list.hidden = true; }
  }, 180);
});
$('#municipality-results').addEventListener('click', (event) => { if (event.target.dataset.name) { $('#municipality-search').value = event.target.dataset.name; $('#municipality-results').hidden = true; } });

$('#address-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget, data = Object.fromEntries(new FormData(form).entries());
  for (const [key, value] of Object.entries(data)) if (value === '') delete data[key];
  form.querySelectorAll('[data-field]').forEach((field) => field.classList.remove('valid', 'invalid', 'not_evaluated'));
  try {
    const result = await request('/api/validate-address', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(data) });
    for (const [field, status] of Object.entries(result)) form.querySelector(`[data-field="${field}"]`)?.classList.add(status.status);
    $('#validation-summary').textContent = Object.entries(result).map(([field, status]) => `${field}: ${status.status}`).join(' · ');
  } catch (cause) { $('#validation-summary').textContent = cause.message; }
});
