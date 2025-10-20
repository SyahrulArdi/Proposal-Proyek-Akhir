// Import modul
const express = require('express');
const path = require('path');
const { createClient } = require('@supabase/supabase-js'); // Import Supabase
const crypto = require('crypto'); // Untuk ID unik

const app = express();
const port = process.env.PORT || 3000;

// --- PENGATURAN SUPABASE ---
// GANTI DENGAN URL DAN KUNCI SUPABASE ANDA DI SINI
const supabaseUrl = 'https://nsqipcsmhgkvcheqpkal.supabase.co'; // <-- GANTI INI DENGAN URL ANDA
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5zcWlwY3NtaGdrdmNoZXFwa2FsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA4Nzg3ODgsImV4cCI6MjA3NjQ1NDc4OH0.FYXUToRAEtamsBVJz10KS90jeuG9abWAPbebyggpY4g'; // <-- GANTI INI DENGAN KUNCI ANON ANDA
// ------------------------------------
// Jangan khawatir, saat deploy ke Vercel, Environment Variables akan digunakan
const actualSupabaseUrl = process.env.SUPABASE_URL || supabaseUrl;
const actualSupabaseKey = process.env.SUPABASE_KEY || supabaseKey;

// Tambahkan penanganan error jika URL/Key tidak valid saat inisialisasi
let supabase;
try {
    supabase = createClient(actualSupabaseUrl, actualSupabaseKey);
    if (!actualSupabaseUrl || !actualSupabaseUrl.startsWith('http')) { // Periksa actualSupabaseUrl
        throw new Error('Supabase URL tidak valid atau belum diatur.');
    }
     if (!actualSupabaseKey || actualSupabaseKey.length < 50) { // Periksa actualSupabaseKey
        throw new Error('Supabase Key tidak valid atau belum diatur.');
    }
} catch (error) {
    console.error("Kesalahan Inisialisasi Supabase:", error.message);
    console.error("Pastikan URL dan Key Supabase sudah benar di server.js atau Environment Variables Vercel.");
    // Hentikan server jika koneksi Supabase gagal di awal
    process.exit(1);
}


// --- PENGATURAN LAIN ---
const userId = 'bank_utama'; // ID pengguna statis
const correctPattern = '1425368'; // <-- Pola Baru (sesuai gambar)
// =========================================================================
// == PENGATURAN DISCORD (OPSIONAL) ==
// =========================================================================
const webhookUrl = "URL_WEBHOOK_DISCORD_ANDA"; // <-- GANTI JIKA PERLU
const actualWebhookUrl = process.env.DISCORD_WEBHOOK_URL || webhookUrl;
// =========================================================================

// Middleware
app.use(express.urlencoded({ extended: true }));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// --- FUNGSI DISCORD (Async) ---
async function sendToDiscord(embedData) {
    // Periksa actualWebhookUrl dan placeholder default
    if (!actualWebhookUrl || actualWebhookUrl === "URL_WEBHOOK_DISCORD_ANDA" || !actualWebhookUrl.startsWith('http')) return;
    const data = { username: 'Log Bank Saya', avatar_url: 'https://i.imgur.com/v1k3rWj.png', embeds: [embedData] };
    try {
        await fetch(actualWebhookUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    } catch (error) { console.error("Gagal mengirim ke Discord:", error); }
}

// --- ROUTES ---

// Rute Lock Screen (GET /)
app.get('/', (req, res) => {
    res.render('lock', { error: req.query.error === '1' });
});

// Rute Proses Unlock (POST /unlock)
app.post('/unlock', (req, res) => {
    const submittedPattern = req.body.pattern;
    if (submittedPattern === correctPattern) {
        res.redirect('/home');
    } else {
        res.redirect('/?error=1');
    }
});

// Rute Home Screen (GET /home)
app.get('/home', (req, res) => {
    res.render('home');
});

// Rute Aplikasi Bank (GET /bank)
app.get('/bank', async (req, res) => {
    try {
        const { data: transactions, error } = await supabase
            .from('transactions')
            .select('*')
            .eq('user_id', userId)
            .order('created_at', { ascending: false });

        if (error) throw error;

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
        console.error("Error di rute GET /bank:", error.message);
        res.status(500).send(`Terjadi kesalahan server: ${error.message}`);
    }
});

// --- Rute API Bank (POST untuk add, edit, delete) ---

// Rute Tambah Transaksi Bank (POST /bank/add)
app.post('/bank/add', async (req, res) => {
    try {
        const { amount, type, description, recipient } = req.body;
        const newTransactionData = { user_id: userId, amount: parseFloat(amount) || 0, type: type, description: description, recipient: (type === 'transfer' || type === 'payment') ? (recipient || null) : null };
        const { data, error } = await supabase.from('transactions').insert([newTransactionData]).select().single();
        if (error) throw error;

        // Log Discord
        let color = 3447003; if (data.type === 'deposit' || data.type === 'reward') color = 3066993; else if (data.type !== 'transfer') color = 15158332;
        const fields = [ { name: 'Tipe', value: data.type, inline: true }, { name: 'Jumlah', value: `Rp ${(data.amount || 0).toLocaleString('id-ID', { minimumFractionDigits: 2 })}`, inline: true } ]; if (data.recipient) fields.push({ name: 'Penerima', value: data.recipient, inline: true });
        const embed = { title: `✅ Transaksi Baru: ${data.description}`, color: color, fields: fields, footer: { text: `User ID: ${userId} | ID Transaksi: ${data.id}` } };
        await sendToDiscord(embed);

        res.redirect('/bank');

    } catch (error) {
        console.error("Error di rute POST /bank/add:", error.message);
        res.status(500).send(`Gagal menambah transaksi: ${error.message}`);
    }
});

// Rute Edit Transaksi Bank (POST /bank/edit)
app.post('/bank/edit', async (req, res) => {
    try {
        const { id, amount, type, description, recipient } = req.body;
        if (!id) return res.status(400).send("ID Transaksi dibutuhkan");
        const updateData = { amount: parseFloat(amount) || 0, type: type, description: description, recipient: (type === 'transfer' || type === 'payment') ? (recipient || null) : null };
        const { data: oldTxData, error: findError } = await supabase.from('transactions').select('description, amount').eq('id', id).eq('user_id', userId).single();
        // Abaikan error 'not found' tapi lempar error lain
        if (findError && findError.code !== 'PGRST116') throw findError;
        const { data: updatedTx, error: updateError } = await supabase.from('transactions').update(updateData).eq('id', id).eq('user_id', userId).select().single();
        if (updateError) throw updateError;
        if (oldTxData && updatedTx) {
             const embed = { title: '✏️ Transaksi Diubah', color: 15844367, description: `**Deskripsi:** \`${oldTxData.description}\` -> \`${updatedTx.description}\`\n**Jumlah:** \`Rp ${(oldTxData.amount || 0).toLocaleString('id-ID', { minimumFractionDigits: 2 })}\` -> \`Rp ${(updatedTx.amount || 0).toLocaleString('id-ID', { minimumFractionDigits: 2 })}\``, footer: { text: `User ID: ${userId} | ID Transaksi: ${id}` } };
             await sendToDiscord(embed);
        }
        res.redirect('/bank');

    } catch (error) {
        console.error("Error di rute POST /bank/edit:", error.message);
        res.status(500).send(`Gagal mengedit transaksi: ${error.details || error.message}`);
    }
});

// Rute Hapus Transaksi Bank (POST /bank/delete)
app.post('/bank/delete', async (req, res) => {
    try {
        const { id } = req.body;
        if (!id) return res.status(400).send("ID Transaksi dibutuhkan");
        const { data: deletedTx, error } = await supabase.from('transactions').delete().eq('id', id).eq('user_id', userId).select().single();
        // Abaikan error 'not found' tapi lempar error lain
        if (error && error.code !== 'PGRST116') throw error;
        if (deletedTx) {
            const embed = { title: '❌ Transaksi Dihapus', color: 15158332, fields: [ { name: 'Deskripsi', value: deletedTx.description, inline: true }, { name: 'Jumlah', value: `Rp ${(deletedTx.amount || 0).toLocaleString('id-ID', { minimumFractionDigits: 2 })}`, inline: true }, { name: 'Tipe', value: deletedTx.type, inline: true } ], footer: { text: `User ID: ${userId} | ID Transaksi: ${id}` } };
            await sendToDiscord(embed);
        }
        res.redirect('/bank');

    } catch (error) {
        console.error("Error di rute POST /bank/delete:", error.message);
        res.status(500).send(`Gagal menghapus transaksi: ${error.message}`);
    }
});

// Jalankan server
app.listen(port, () => {
    console.log(`Server berjalan di http://localhost:${port}`);
});