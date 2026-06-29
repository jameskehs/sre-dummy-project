import express from 'express'
import os from 'os'

const app = express()
const port = process.env.PORT || 3000

app.set('view engine', 'ejs')

app.get('/', (req, res) => {
    res.render('index', { variableName: os.hostname() })
})

app.get('/health', (req, res) => {
    res.json({"status": "ok"})
})

app.listen(port, () => {
  console.log(`Example app listening on port ${port}`)
})