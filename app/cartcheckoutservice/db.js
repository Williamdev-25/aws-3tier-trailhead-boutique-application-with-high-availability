const { Pool } = require("pg");
const fs = require("fs");
const path = require("path");

const pool = new Pool({
  host: process.env.DB_HOST || "localhost",
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || "appdb",
  user: process.env.DB_USER || "dbadmin",
  password: process.env.DB_PASSWORD || "",
  max: 10,
  ssl:
    process.env.DB_SSL === "true"
      ? { rejectUnauthorized: false }
      : false,
});

async function init() {
  const schema = fs.readFileSync(path.join(__dirname, "init.sql"), "utf-8");
  await pool.query(schema);
  console.log("cartcheckoutservice: database schema ready");
}

module.exports = { pool, init };
