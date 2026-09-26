// Comments backend for the restroom-gap site (Google Apps Script, bound to a Google Sheet).
// Paste into Extensions > Apps Script of the Sheet, then Deploy > New deployment > Web app
// (Execute as: Me; Who has access: Anyone). The site reads comments with GET and adds them with POST.
// Each comment is one row in the "Comments" tab: time | section | name | comment. Delete a row to remove a comment.

function sheet_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName('Comments');
  if (!sh) {
    sh = ss.insertSheet('Comments');
    sh.appendRow(['time', 'section', 'name', 'comment']);
  }
  return sh;
}

function doGet(e) {
  const rows = sheet_().getDataRange().getValues().slice(1)
    .filter(r => String(r[3]).trim() !== '')
    .map(r => ({ time: r[0], section: String(r[1]), name: String(r[2]), comment: String(r[3]) }));
  return ContentService.createTextOutput(JSON.stringify(rows))
    .setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  const clip = (s, n) => String(s || '').slice(0, n).trim();
  const safe = s => (/^[=+\-@]/.test(s) ? "'" + s : s);   // stop text being read as a spreadsheet formula
  let d = {};
  try { d = JSON.parse((e && e.postData && e.postData.contents) || '{}'); } catch (err) { d = {}; }
  const comment = clip(d.comment, 2000);
  if (!comment) return ContentService.createTextOutput('empty');
  sheet_().appendRow([new Date(), safe(clip(d.section, 40)), safe(clip(d.name, 60)), safe(comment)]);
  return ContentService.createTextOutput('ok');
}
