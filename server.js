// Import modul
const express = require('express');
const path = require('path');
const { createClient } = require('@supabase/supabase-js'); // Import Supabase

const app = express();
const port = process.env.PORT || 3000;

// --- PENGATURAN SUPABASE ---
// AMBIL DARI DASHBOARD SUPABASE ANDA & SIMPAN DI ENVIRONMENT VARIABLES NANTI
const supabaseUrl = process.env.SUPABASE_URL || 'URL_SUPABASE_ANDA'; // Ganti sementara atau gunakan env var
const supabaseKey = process.env.SUPABASE_KEY || 'KUNCI_ANON_SUPABASE_ANDA'; // Ganti sementara atau gunakan env var
const supabase = createClient(supabaseUrl, supabaseKey);

// --- PENGATURAN LAIN ---
const userId = 'bank_utama'; // ID pengguna statis

// =========================================================================
// == PENGATURAN DISCORD (OPSIONAL, MASIH BISA DIPAKAI) ==
// =========================================================================
const webhookUrl = process.env.DISCORD_WEBHOOK_URL || "https://discord.com/api/webhooks/1247375576491364463/4yPNqOQhBk-0HRho3Fd55GfWfL4mWw0-Wi13i-J3yAcObbeejxs2-OLUsmI7aXml9sEB";
// =========================================================================

// Middleware
app.use(express.urlencoded({ extended: true }));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// --- FUNGSI DISCORD (Async) ---
async function sendToDiscord(embedData) {
    if (!webhookUrl || webhookUrl === "YOUR_DISCORD_WEBHOOK_URL") return; // Jangan kirim jika URL tidak diatur
    const data = { username: 'Log Bank Saya', avatar_url: 'https://i.imgur.com/v1k3rWj.png', embeds: [embedData] };
    try {
        await fetch(webhookUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    } catch (error) { console.error("Gagal mengirim ke Discord:", error); }
}

// --- ROUTES ---

// Rute utama (GET /)
app.get('/', async (req, res) => {
    try {
        // Ambil data dari Supabase
        const { data: transactions, error } = await supabase
            .from('transactions')
            .select('*')
            .eq('user_id', userId) // Hanya ambil milik user_id ini
            .order('created_at', { ascending: false }); // Urutkan terbaru dulu

        if (error) throw error;

        // Hitung total dan saldo (logika sama seperti sebelumnya)
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

        res.render('bank', { balance, totals, transactions });

    } catch (error) {
        console.error("Error di rute GET /:", error.message);
        res.status(500).send(`Terjadi kesalahan server: ${error.message}`);
    }
});

// Rute untuk menambah transaksi (POST /add)
app.post('/add', async (req, res) => {
    try {
        const { amount, type, description, recipient } = req.body;
        const newTransactionData = {
            user_id: userId,
            amount: parseFloat(amount) || 0,
            type: type,
            description: description,
            recipient: (type === 'transfer' || type === 'payment') ? (recipient || null) : null,
            // created_at dan id akan dibuat otomatis oleh Supabase
        };

        // Masukkan data ke Supabase
        const { data, error } = await supabase
            .from('transactions')
            .insert([newTransactionData])
            .select() // Ambil data yang baru saja dimasukkan
            .single(); // Karena kita hanya memasukkan satu

        if (error) throw error;

        // Kirim log Discord (menggunakan data dari Supabase)
        const newTx = data; // data yg dikembalikan supabase setelah insert
        let color = 3447003;
        if (newTx.type === 'deposit' || newTx.type === 'reward') color = 3066993;
        else if (newTx.type !== 'transfer') color = 15158332;
        const fields = [ { name: 'Tipe', value: newTx.type, inline: true }, { name: 'Jumlah', value: `Rp ${(newTx.amount || 0).toLocaleString('id-ID', { minimumFractionDigits: 2 })}`, inline: true } ];
        if (newTx.recipient) fields.push({ name: 'Penerima', value: newTx.recipient, inline: true });
        const embed = { title: `✅ Transaksi Baru: ${newTx.description}`, color: color, fields: fields, footer: { text: `User ID: ${userId} | ID Transaksi: ${newTx.id}` } };
        await sendToDiscord(embed);

        res.redirect('/');

    } catch (error) {
        console.error("Error di rute POST /add:", error.message);
        res.status(500).send(`Gagal menambah transaksi: ${error.message}`);
    }
});

// Rute untuk mengedit transaksi (POST /edit)
app.post('/edit', async (req, res) => {
    try {
        const { id, amount, type, description, recipient } = req.body;
        if (!id) return res.status(400).send("ID Transaksi dibutuhkan");

        const updateData = {
            amount: parseFloat(amount) || 0,
            type: type,
            description: description,
            recipient: (type === 'transfer' || type === 'payment') ? (recipient || null) : null,
        };

        // Ambil data lama sebelum update (untuk log Discord)
         const { data: oldTxData, error: findError } = await supabase
            .from('transactions')
            .select('description, amount')
            .eq('id', id)
            .eq('user_id', userId)
            .single();

         if (findError && findError.code !== 'PGRST116') { // Abaikan error 'not found'
             throw findError;
         }

        // Update data di Supabase
        const { data: updatedTx, error: updateError } = await supabase
            .from('transactions')
            .update(updateData)
            .eq('id', id)
            .eq('user_id', userId) // Pastikan hanya bisa edit milik sendiri
            .select()
            .single();

        if (updateError) throw updateError;

        // Kirim log Discord jika data lama ditemukan
        if (oldTxData && updatedTx) {
             const embed = { title: '✏️ Transaksi Diubah', color: 15844367, description: `**Deskripsi:** \`${oldTxData.description}\` -> \`${updatedTx.description}\`\n**Jumlah:** \`Rp ${(oldTxData.amount || 0).toLocaleString('id-ID', { minimumFractionDigits: 2 })}\` -> \`Rp ${(updatedTx.amount || 0).toLocaleString('id-ID', { minimumFractionDigits: 2 })}\``, footer: { text: `User ID: ${userId} | ID Transaksi: ${id}` } };
             await sendToDiscord(embed);
        } else {
             console.warn(`Edit berhasil tapi data lama tidak ditemukan untuk log Discord (ID: ${id})`);
        }

        res.redirect('/');

    } catch (error) {
        console.error("Error di rute POST /edit:", error.message);
         // Tampilkan pesan error detail dari Supabase jika ada
         const detail = error.details || error.message;
        res.status(500).send(`Gagal mengedit transaksi: ${detail}`);
    }
});

// Rute untuk menghapus transaksi (POST /delete)
app.post('/delete', async (req, res) => {
    try {
        const { id } = req.body;
        if (!id) return res.status(400).send("ID Transaksi dibutuhkan");

        // Hapus data dari Supabase dan kembalikan data yg dihapus
        const { data: deletedTx, error } = await supabase
            .from('transactions')
            .delete()
            .eq('id', id)
            .eq('user_id', userId) // Pastikan hanya bisa hapus milik sendiri
            .select() // Kembalikan data yang dihapus
            .single(); // Hanya satu baris

         // Jika error bukan karena tidak ketemu, lempar error
        if (error && error.code !== 'PGRST116') {
             throw error;
         }

        // Kirim log Discord jika penghapusan berhasil
        if (deletedTx) {
            const embed = { title: '❌ Transaksi Dihapus', color: 15158332, fields: [ { name: 'Deskripsi', value: deletedTx.description, inline: true }, { name: 'Jumlah', value: `Rp ${(deletedTx.amount || 0).toLocaleString('id-ID', { minimumFractionDigits: 2 })}`, inline: true }, { name: 'Tipe', value: deletedTx.type, inline: true } ], footer: { text: `User ID: ${userId} | ID Transaksi: ${id}` } };
            await sendToDiscord(embed);
        } else {
             console.warn(`Hapus gagal atau transaksi tidak ditemukan (ID: ${id})`);
        }

        res.redirect('/');

    } catch (error) {
        console.error("Error di rute POST /delete:", error.message);
        res.status(500).send(`Gagal menghapus transaksi: ${error.message}`);
    }
});

// Jalankan server
app.listen(port, () => {
    console.log(`Server berjalan di http://localhost:${port}`);
});