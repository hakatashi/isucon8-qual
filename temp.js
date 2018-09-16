const mysql = require('mysql');
const connection = mysql.createConnection({
  host     : 'localhost',
  user     : 'root',
  password : '',
  database : 'torb'
});

const map = new Map();
const counter = new Map();
const seatrank = new Map([
  ...Array(50).fill('S'),
  ...Array(150).fill('A'),
  ...Array(300).fill('B'),
  ...Array(500).fill('C'),
].map((rank, index) => [index + 1, rank]))

connection.connect();

connection.query('SELECT * FROM reservations WHERE canceled_at IS NULL ORDER BY updated_at', async (error, results) => {
  if (error) throw error;
  for (const result of results) {
    const key = JSON.stringify([result.event_id, result.sheet_id]);
    map.set(key, result);
    const key2 = JSON.stringify([result.event_id, seatrank.get(result.sheet_id)]);
    const count = counter.get(key2) || 0;
    counter.set(key2, count + 1);
  }
  console.log(map.size, counter.size);
  let i = 0;
  /*
  for (const [key, result] of map.entries()) {
    const [event_id, sheet_id] = JSON.parse(key);
    i++;
    if (i % 100 === 0) {
      console.log(i);
    }
    await new Promise((resolve, reject) => {
      connection.query('INSERT IGNORE INTO sheetstates (event_id, sheet_id, user_id, reserved_at) VALUES (?, ?, ?, ?)', [event_id, sheet_id, result.user_id, result.reserved_at], (error, result) => {
        if (error) {
          reject(error);
        } else {
          resolve();
        }
      });
    })
  }
  */
  for (const [key, count] of counter.entries()) {
    const [event_id, rank] = JSON.parse(key);
    i++;
    if (i % 100 === 0) {
      console.log(i);
    }
    await new Promise((resolve, reject) => {
      connection.query('INSERT IGNORE INTO sheetcounts (event_id, `rank`, count) VALUES (?, ?, ?)', [event_id, rank, count], (error, result) => {
        if (error) {
          reject(error);
        } else {
          resolve();
        }
      });
    });
  }
  connection.end();
});