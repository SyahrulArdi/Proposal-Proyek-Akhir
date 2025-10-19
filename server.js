// Import modul yang dibutuhkan
const express = require('express');
const fs = require('fs').promises; // Gunakan versi promise dari fs
const path = require('path');
const crypto = require('crypto'); // Untuk ID unik

const app = express();
const port = process.env.PORT || 3000; // Port untuk server

// --- PENGATURAN ---
const userId = 'bank_utama'; // ID pengguna statis
const jsonFile = path.join(__dirname, 'transactions.json'); // Path ke file JSON

// =========================================================================
// == PENGATURAN DISCORD ==
// =========================================================================
const webhookUrl = "https://discord.com/api/webhooks/1247375576491364463/4yPNqOQhBk-0HRho3Fd55GfWfL4mWw0-Wi13i-J3yAcObbeejxs2-OLUsmI7aXml9sEB";
// =========================================================================

// Middleware untuk membaca body request (form data)
app.use(express.urlencoded({ extended: true }));

// Set EJS sebagai view engine
// Ini memberitahu Express untuk mencari file di folder 'views'
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// --- FUNGSI UNTUK DATA JSON ---

/**
 * Membaca semua transaksi dari file JSON (Async)
 * @returns {Promise<Array>} Array transaksi
 */
async function readTransactions() {
    try {
        await fs.access(jsonFile); // Cek apakah file ada
        const jsonData = await fs.readFile(jsonFile, 'utf-8');
        return JSON.parse(jsonData) || [];
    } catch (error) {
        // Jika file tidak ada atau error baca, kembalikan array kosong
        return [];
    }
}

/**
 * Menyimpan semua transaksi ke file JSON (Async)
 * @param {Array} data Array transaksi
 * @returns {Promise<void>}
 */
async function saveTransactions(data) {
    try {
        // Gunakan JSON.stringify dengan spasi 2 untuk pretty print
        await fs.writeFile(jsonFile, JSON.stringify(data, null, 2), 'utf-8');
    } catch (error) {
        console.error("Gagal menyimpan transaksi:", error);
    }
}

// --- FUNGSI DISCORD (Async) ---
async function sendToDiscord(embedData) {
    const data = {
        username: 'Log Bank Saya',
        avatar_url: 'https://i.imgur.com/v1k3rWj.png',
        embeds: [embedData]
    };
    try {
        // Fetch sudah built-in di Node.js v18+
        await fetch(webhookUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
    } catch (error) {
        console.error("Gagal mengirim ke Discord:", error);
    }
}

// --- FUNGSI LOGIKA TRANSAKSI ---

function getUserTransactions(allTx, currentUserId) {
    return allTx.filter(tx => tx.user_id === currentUserId);
}

function getTransactionKeyById(allTx, id, currentUserId) {
    return allTx.findIndex(tx => tx.id === id && tx.user_id === currentUserId);
}

// --- ROUTES (RUTE HALAMAN) ---

// Rute utama (GET /) - Menampilkan halaman bank
app.get('/', async (req, res) => {
    try {
        const allTransactions = await readTransactions();
        const transactions = getUserTransactions(allTransactions, userId);

        // Urutkan transaksi (terbaru dulu)
        transactions.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

        // Hitung total dan saldo
        const totals = { total_deposit: 0, total_withdraw: 0, total_transfer: 0, total_payment: 0, total_reward: 0 };
        transactions.forEach(tx => {
            const amount = parseFloat(tx.amount) || 0;
            switch (tx.type) {
                case 'deposit': totals.total_deposit += amount; break;
                case 'withdraw': totals.total_withdraw += amount; break;
                case 'transfer': totals.total_transfer += amount; break;
                case 'payment': totals.total_payment += amount; break;
                case 'reward': totals.total_reward += amount; break;
            }
        });

        const balance = (totals.total_deposit || 0) - (totals.total_withdraw || 0) - (totals.total_transfer || 0) - (totals.total_payment || 0) + (totals.total_reward || 0);

        // Render halaman EJS dan kirim data
        // Ini akan mencari file 'views/bank.ejs'
        res.render('bank', {
            balance,
            totals,
            transactions
        });

    } catch (error) {
        console.error("Error di rute GET /:", error);
        res.status(500).send("Terjadi kesalahan server");
    }
});

// Rute untuk menambah transaksi (POST /add)
app.post('/add', async (req, res) => {
    try {
        const allTransactions = await readTransactions();
        const newTransaction = {
            id: crypto.randomUUID(), // ID unik
            user_id: userId,
            amount: parseFloat(req.body.amount) || 0,
            type: req.body.type,
            description: req.body.description,
            recipient: req.body.recipient || null,
            created_at: new Date().toISOString() // Format waktu standar ISO
        };

        allTransactions.push(newTransaction);
        await saveTransactions(allTransactions);

        // Kirim log Discord
        let color = 3447003; // Biru default
        if (newTransaction.type === 'deposit' || newTransaction.type === 'reward') color = 3066993; // Hijau
        else if (newTransaction.type !== 'transfer') color = 15158332; // Merah

        const fields = [
            { name: 'Tipe', value: newTransaction.type, inline: true },
            { name: 'Jumlah', value: `Rp ${newTransaction.amount.toLocaleString('id-ID', { minimumFractionDigits: 2 })}`, inline: true },
        ];
        if (newTransaction.recipient) {
            fields.push({ name: 'Penerima', value: newTransaction.recipient, inline: true });
        }
        const embed = { title: `✅ Transaksi Baru: ${newTransaction.description}`, color: color, fields: fields, footer: { text: `User ID: ${userId} | ID Transaksi: ${newTransaction.id}` } };
        await sendToDiscord(embed);

        res.redirect('/'); // Kembali ke halaman utama

    } catch (error) {
        console.error("Error di rute POST /add:", error);
        res.status(500).send("Gagal menambah transaksi");
    }
});

// Rute untuk mengedit transaksi (POST /edit)
app.post('/edit', async (req, res) => {
    try {
        const id = req.body.id; // Ambil id dari body
        if (!id) return res.status(400).send("ID Transaksi dibutuhkan");

        const allTransactions = await readTransactions();
        const key = getTransactionKeyById(allTransactions, id, userId);

        if (key !== -1) { // findIndex mengembalikan -1 jika tidak ketemu
            const oldTx = { ...allTransactions[key] }; // Salin data lama

            // Update data
            allTransactions[key].amount = parseFloat(req.body.amount) || 0;
            allTransactions[key].type = req.body.type;
            allTransactions[key].description = req.body.description;
            allTransactions[key].recipient = req.body.type === 'transfer' || req.body.type === 'payment' ? (req.body.recipient || null) : null;

            const newTx = allTransactions[key];
            await saveTransactions(allTransactions);

            // Kirim log Discord
            const embed = { title: '✏️ Transaksi Diubah', color: 15844367, description: `**Deskripsi:** \`${oldTx.description}\` -> \`${newTx.description}\`\n**Jumlah:** \`Rp ${oldTx.amount.toLocaleString('id-ID', { minimumFractionDigits: 2 })}\` -> \`Rp ${newTx.amount.toLocaleString('id-ID', { minimumFractionDigits: 2 })}\``, footer: { text: `User ID: ${userId} | ID Transaksi: ${id}` } };
            await sendToDiscord(embed);
        } else {
            console.warn(`Edit gagal: Transaksi ID ${id} tidak ditemukan untuk user ${userId}`);
        }
        res.redirect('/');

    } catch (error) {
        console.error("Error di rute POST /edit:", error);
        res.status(500).send("Gagal mengedit transaksi");
    }
});


// Rute untuk menghapus transaksi (POST /delete)
app.post('/delete', async (req, res) => {
    try {
        const id = req.body.id; // Ambil id dari body
        if (!id) return res.status(400).send("ID Transaksi dibutuhkan");

        let allTransactions = await readTransactions();
        const key = getTransactionKeyById(allTransactions, id, userId);

        if (key !== -1) {
            const deletedTx = allTransactions[key]; // Ambil data sebelum dihapus
            
            // Hapus elemen dari array
            allTransactions.splice(key, 1); 
            
            await saveTransactions(allTransactions); // Simpan kembali ke file
            
            const embed = { title: '❌ Transaksi Dihapus', color: 15158332, fields: [ { name: 'Deskripsi', value: deletedTx.description, inline: true }, { name: 'Jumlah', value: `Rp ${deletedTx.amount.toLocaleString('id-ID', { minimumFractionDigits: 2 })}`, inline: true }, { name: 'Tipe', value: deletedTx.type, inline: true } ], footer: { text: `User ID: ${userId} | ID Transaksi: ${id}` } };
            await sendToDiscord(embed);
        } else {
            console.warn(`Hapus gagal: Transaksi ID ${id} tidak ditemukan untuk user ${userId}`);
        }
        res.redirect('/');

    } catch (error) {
        console.error("Error di rute POST /delete:", error);
        res.status(500).send("Gagal menghapus transaksi");
    }
});


// Jalankan server
app.listen(port, () => {
    console.log(`Server berjalan di http://localhost:${port}`);
});