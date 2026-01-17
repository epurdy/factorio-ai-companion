const fs = require('fs');
const path = 'C:/Users/lveil/AppData/Local/Temp/claude/C--Users-lveil-Desktop-Projects-factorio-ai-companion/tasks/bcdff1d.output';

let lastSize = 0;
try {
  const stats = fs.statSync(path);
  lastSize = stats.size;
} catch (e) {
  // File doesn't exist yet
}

const checkInterval = 1000;
const timeout = 120000;
const startTime = Date.now();

const check = () => {
  if (Date.now() - startTime > timeout) {
    console.log('TIMEOUT');
    process.exit(1);
  }

  try {
    const stats = fs.statSync(path);
    if (stats.size > lastSize) {
      const content = fs.readFileSync(path, 'utf8');
      console.log(content);
      process.exit(0);
    }
  } catch (e) {
    if (e.code !== 'ENOENT') {
      console.error(e);
    }
  }

  setTimeout(check, checkInterval);
};

check();
