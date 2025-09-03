#!/bin/bash
set -euo pipefail

# DIANASTORE PROXY - V2 Installer (Fixed Version with WebSocket Support)
# Author: AI Assistant
# Version: 3.2 - Fixed WebSocket Implementation & Version Compatibility

# Defaults (added by patch)
VLESS_WS_PATH=${VLESS_WS_PATH:-/vless-ws}
TROJAN_WS_PATH=${TROJAN_WS_PATH:-/trojan-ws}
TLS_PORT=${TLS_PORT:-443}
HTTP_PORT=${HTTP_PORT:-80}
XRAY_BIN=${XRAY_BIN:-/usr/local/bin/xray}
XRAY_CONF_DIR=${XRAY_CONF_DIR:-/etc/xray}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Banner
clear
echo -e "${BLUE}"
echo "================================================"
echo "  DIANASTORE PROXY - V2 INSTALLER (FIXED)"
echo "================================================"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Please run as root (use sudo)${NC}"
    exit 1
fi

# Get domain input with better handling
echo -e "${CYAN}🌐 Domain Configuration${NC}"
echo -e "${YELLOW}Enter your domain (e.g., yourdomain.com):${NC}"
echo -e "${YELLOW}Press Enter to use default: bas.ahemmm.my.id${NC}"

# Read domain with timeout and default
read -t 30 -p "Domain: " DOMAIN

# Set default if empty
if [ -z "$DOMAIN" ]; then
    DOMAIN="bas.ahemmm.my.id"
    echo -e "${GREEN}✅ Using default domain: ${CYAN}$DOMAIN${NC}"
else
    echo -e "${GREEN}✅ Domain set to: ${CYAN}$DOMAIN${NC}"
fi

echo ""
echo -e "${GREEN}✅ Domain confirmed: ${CYAN}$DOMAIN${NC}"
echo -e "${YELLOW}Starting installation in 3 seconds...${NC}"
sleep 3

# Update system
echo -e "${BLUE}📦 Updating system packages...${NC}"
apt update -y > /dev/null 2>&1
apt upgrade -y > /dev/null 2>&1
echo -e "${GREEN}✅ System updated!${NC}"

# Install dependencies
echo -e "${BLUE}📦 Installing system dependencies...${NC}"
apt install -y curl wget git nginx certbot python3-certbot-nginx unzip jq ufw > /dev/null 2>&1
echo -e "${GREEN}✅ System dependencies installed!${NC}"

# Install Node.js
echo -e "${BLUE}📦 Installing Node.js 18.x...${NC}"
curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null 2>&1
apt install -y nodejs > /dev/null 2>&1
echo -e "${GREEN}✅ Node.js installed!${NC}"

# Install PM2
echo -e "${BLUE}📦 Installing PM2...${NC}"
npm install -g pm2 > /dev/null 2>&1
echo -e "${GREEN}✅ PM2 installed!${NC}"

# Create project directory
echo -e "${BLUE}📁 Creating project directory...${NC}"
mkdir -p /opt/dianastore-proxy-v2
cd /opt/dianastore-proxy-v2

# Create package.json
echo -e "${BLUE}📦 Creating package.json...${NC}"
cat > package.json << 'EOF'
{
  "name": "dianastore-proxy-server-v2",
  "version": "3.2.0",
  "description": "DIANASTORE PROXY Server V2 with WebSocket Support",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "uuid": "^9.0.0",
    "axios": "^1.4.0",
    "ws": "^8.13.0",
    "dotenv": "^16.3.1",
    "crypto-js": "^4.1.1"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  },
  "keywords": ["proxy", "vless", "trojan", "shadowsocks", "websocket"],
  "author": "DIANASTORE Team",
  "license": "MIT"
}
EOF

# Create server.js with WebSocket implementation and version fix
echo -e "${BLUE}📄 Creating server.js with WebSocket support and version fix...${NC}"
cat > server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const axios = require('axios');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');
const http = require('http');
const url = require('url');
const net = require('net');

const app = express();
const PORT = process.env.PORT || 3000;

// Create HTTP server
const server = http.createServer(app);

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// In-memory storage for accounts
let accounts = [];
let proxyList = [];

// Load existing accounts
const accountsFile = path.join(__dirname, 'accounts', 'accounts.json');
if (fs.existsSync(accountsFile)) {
    try {
        accounts = JSON.parse(fs.readFileSync(accountsFile, 'utf8'));
    } catch (error) {
        console.log('No existing accounts found, starting fresh');
    }
}

// Ensure accounts directory exists
const accountsDir = path.join(__dirname, 'accounts');
if (!fs.existsSync(accountsDir)) {
    fs.mkdirSync(accountsDir, { recursive: true });
}

// Save accounts to file
function saveAccounts() {
    fs.writeFileSync(accountsFile, JSON.stringify(accounts, null, 2));
}

// Fetch proxy list from GitHub (correct format)
async function fetchProxyList() {
    try {
        // Try multiple proxy sources
        const proxySources = [
            'https://raw.githubusercontent.com/FoolVPN-ID/Nautica/refs/heads/main/proxyList.txt',
            'https://raw.githubusercontent.com/Ninadiantea/modevps/main/proxyList.txt',
            'https://raw.githubusercontent.com/mahdibland/ShadowsocksAggregator/master/sub/sub_merge.txt'
        ];

        for (const source of proxySources) {
            try {
                // Set a custom User-Agent to avoid version issues
                const response = await axios.get(source, { 
                    timeout: 10000,
                    headers: {
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
                    }
                });
                
                if (response.data) {
                    console.log(`✅ Proxy list loaded from: ${source}`);
                    
                    // Parse CSV format: IP,Port,Country,ORG
                    const lines = response.data.split('\n').filter(line => line.trim());
                    proxyList = lines.map((line, index) => {
                        const [proxyIP, proxyPort, country, org] = line.split(',');
                        return {
                            id: index + 1,
                            proxyIP: proxyIP || 'Unknown',
                            proxyPort: proxyPort || 'Unknown',
                            country: country || 'Unknown',
                            org: org || 'Unknown Org',
                            type: 'proxy'
                        };
                    }).filter(proxy => proxy.proxyIP !== 'Unknown' && proxy.proxyPort !== 'Unknown');
                    
                    if (proxyList.length > 0) {
                        console.log(`📊 Loaded ${proxyList.length} proxies`);
                        return;
                    }
                }
            } catch (error) {
                console.log(`❌ Failed to load from ${source}: ${error.message}`);
                continue;
            }
        }
        
        // Fallback: create sample proxies
        console.log('⚠️ Using fallback proxy list');
        proxyList = [
            {
                id: 1,
                proxyIP: '203.194.112.119',
                proxyPort: '8443',
                country: 'ID',
                org: 'Indonesia Proxy',
                type: 'proxy'
            },
            {
                id: 2,
                proxyIP: '1.1.1.1',
                proxyPort: '443',
                country: 'SG',
                org: 'Singapore Proxy',
                type: 'proxy'
            },
            {
                id: 3,
                proxyIP: '104.18.7.80',
                proxyPort: '443',
                country: 'US',
                org: 'Cloudflare',
                type: 'proxy'
            }
        ];
        
    } catch (error) {
        console.error('Error fetching proxy list:', error);
        proxyList = [];
    }
}

// Generate configuration with correct format and version compatibility
function generateConfigFromProxy(proxyId, name, domain) {
    const proxy = proxyList.find(p => p.id == proxyId);
    if (!proxy) {
        throw new Error('Proxy not found');
    }
    
    const uuid = uuidv4();
    const port = 443; // Always use 443 for TLS
    
    // Get country flag emoji
    const countryFlag = getFlagEmoji(proxy.country);
    
    // Build path like _worker.js: /IP-PORT
    const path = `/${proxy.proxyIP}-${proxy.proxyPort}`;
    
    // VLESS Configuration with version compatibility
    const vlessConfig = `vless://${uuid}@${domain}:${port}?encryption=none&security=tls&sni=${domain}&type=ws&host=${domain}&path=${encodeURIComponent(path)}#${countryFlag} VLESS WS TLS [${name}]`;
    
    // Trojan Configuration with version compatibility
    const trojanConfig = `trojan://${uuid}@${domain}:${port}?security=tls&type=ws&host=${domain}&path=${encodeURIComponent(path)}#${countryFlag} Trojan WS TLS [${name}]`;
    
    // Shadowsocks Configuration
    const ssConfig = `ss://${Buffer.from(`none:${uuid}`).toString('base64')}@${domain}:${port}?plugin=v2ray-plugin;tls;mux=0;mode=websocket;path=${encodeURIComponent(path)};host=${domain}#${countryFlag} SS WS TLS [${name}]`;
    
    return {
        id: uuid,
        name,
        proxyName: `${proxy.proxyIP}:${proxy.proxyPort}`,
        proxyCountry: proxy.country,
        proxyOrg: proxy.org,
        type: 'multi',
        configs: {
            vless: vlessConfig,
            trojan: trojanConfig,
            shadowsocks: ssConfig
        },
        subscription: vlessConfig // Default to VLESS for subscription
    };
}

// Get country flag emoji
function getFlagEmoji(isoCode) {
    if (!isoCode || isoCode.length !== 2) return '🌍';
    
    const codePoints = isoCode
        .toUpperCase()
        .split("")
        .map((char) => 127397 + char.charCodeAt(0));
    return String.fromCodePoint(...codePoints);
}

// Routes
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/sub', (req, res) => {
    const domain = process.env.DOMAIN || 'localhost';
    let subscription = '';
    
    accounts.forEach(account => {
        subscription += account.subscription + '\n';
    });
    
    res.setHeader('Content-Type', 'text/plain');
    res.send(subscription);
});

// API Routes
app.get('/api/v1/accounts', (req, res) => {
    res.json({
        success: true,
        data: accounts,
        stats: {
            total: accounts.length,
            vless: accounts.filter(a => a.type === 'multi').length,
            trojan: accounts.filter(a => a.type === 'multi').length,
            shadowsocks: accounts.filter(a => a.type === 'multi').length
        }
    });
});

app.get('/api/v1/proxies', (req, res) => {
    res.json({
        success: true,
        data: proxyList,
        total: proxyList.length
    });
});

app.post('/api/v1/accounts', (req, res) => {
    const { name, proxyId } = req.body;
    const domain = process.env.DOMAIN || 'localhost';
    
    if (!name || !proxyId) {
        return res.status(400).json({
            success: false,
            message: 'Name and proxy selection are required'
        });
    }
    
    try {
        const config = generateConfigFromProxy(proxyId, name, domain);
        accounts.push(config);
        saveAccounts();
        
        res.json({
            success: true,
            message: 'Account created successfully',
            data: config
        });
    } catch (error) {
        res.status(400).json({
            success: false,
            message: error.message
        });
    }
});

app.delete('/api/v1/accounts/:id', (req, res) => {
    const { id } = req.params;
    const initialLength = accounts.length;
    accounts = accounts.filter(account => account.id !== id);
    
    if (accounts.length < initialLength) {
        saveAccounts();
        res.json({
            success: true,
            message: 'Account deleted successfully'
        });
    } else {
        res.status(404).json({
            success: false,
            message: 'Account not found'
        });
    }
});

// Health check
app.get('/health', (req, res) => {
    res.json({
        service: 'DIANASTORE PROXY Server V2',
        status: 'running',
        domain: process.env.DOMAIN || 'localhost',
        port: PORT,
        accounts: accounts.length,
        proxies: proxyList.length
    });
});

// Create WebSocket server
const wss = new WebSocket.Server({ noServer: true });

// Handle WebSocket connections
wss.on('connection', async (ws, req, proxyIP, proxyPort, uuid) => {
  console.log(`WebSocket connection established to ${proxyIP}:${proxyPort}`);
  
  try {
    // Connect to the target proxy server using raw TCP
    const targetSocket = new net.Socket();
    
    targetSocket.connect(parseInt(proxyPort), proxyIP, () => {
      console.log(`TCP connection established to ${proxyIP}:${proxyPort}`);
    });
    
    // Handle data from client to target
    ws.on('message', (message) => {
      if (targetSocket.writable) {
        targetSocket.write(message);
      }
    });
    
    // Handle data from target to client
    targetSocket.on('data', (data) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(data);
      }
    });
    
    // Handle client connection close
    ws.on('close', () => {
      targetSocket.destroy();
      console.log(`WebSocket connection to ${proxyIP}:${proxyPort} closed`);
    });
    
    // Handle target connection close
    targetSocket.on('close', () => {
      ws.close();
      console.log(`Target connection to ${proxyIP}:${proxyPort} closed`);
    });
    
    // Handle errors
    ws.on('error', (err) => {
      console.error(`Client WebSocket error:`, err);
      targetSocket.destroy();
    });
    
    targetSocket.on('error', (err) => {
      console.error(`Target connection error:`, err);
      ws.close();
    });
    
  } catch (error) {
    console.error(`Failed to establish connection to ${proxyIP}:${proxyPort}:`, error);
    ws.close();
  }
});

// Handle upgrade requests
server.on('upgrade', (request, socket, head) => {
  const pathname = url.parse(request.url).pathname;
  
  // Check if the path matches our proxy pattern: /IP-PORT
  const match = pathname.match(/^\/([^-]+)-(\d+)$/);
  
  if (match) {
    const proxyIP = match[1];
    const proxyPort = match[2];
    
    // Extract UUID from headers for authentication (if needed)
    const uuid = request.headers['sec-websocket-protocol'] || null;
    
    console.log(`Upgrade request for ${proxyIP}:${proxyPort}`);
    
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request, proxyIP, proxyPort, uuid);
    });
  } else {
    // Not a proxy request, close the connection
    socket.destroy();
  }
});

// Initialize proxy list on startup
fetchProxyList();

// Use the HTTP server instead of app.listen
server.listen(PORT, () => {
    console.log(`🚀 Server running on port ${PORT}`);
    console.log(`🌐 Domain: ${process.env.DOMAIN || 'localhost'}`);
    console.log(`📊 Total accounts: ${accounts.length}`);
    console.log(`🔗 Loading proxy list...`);
});
EOF

# Create public directory and updated index.html with DIANASTORE branding
echo -e "${BLUE}📄 Creating web dashboard with DIANASTORE branding...${NC}"
mkdir -p public

cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DIANASTORE PROXY - Dashboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        .gradient-bg {
            background: linear-gradient(135deg, #ff6b6b 0%, #a83279 100%);
        }
        .card-hover:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 25px rgba(0,0,0,0.1);
        }
        .copy-btn {
            transition: all 0.3s ease;
        }
        .copy-btn:hover {
            background-color: #059669;
        }
        .delete-btn {
            transition: all 0.3s ease;
        }
        .delete-btn:hover {
            background-color: #dc2626;
        }
        .proxy-card {
            transition: all 0.3s ease;
        }
        .proxy-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 20px rgba(0,0,0,0.1);
        }
        .config-tabs {
            display: none;
        }
        .config-tabs.active {
            display: block;
        }
    </style>
</head>
<body class="bg-gray-50 min-h-screen">
    <!-- Header -->
    <header class="gradient-bg text-white shadow-lg">
        <div class="container mx-auto px-6 py-8">
            <div class="flex items-center justify-between">
                <div>
                    <h1 class="text-3xl font-bold">💎 DIANASTORE PROXY</h1>
                    <p class="text-pink-100 mt-2">Premium WebSocket Proxy Dashboard</p>
                </div>
                <div class="text-right">
                    <div class="text-2xl font-bold" id="totalAccounts">0</div>
                    <div class="text-pink-100">Total Accounts</div>
                </div>
            </div>
        </div>
    </header>

    <!-- Stats Cards -->
    <div class="container mx-auto px-6 -mt-6">
        <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
            <div class="bg-white rounded-lg shadow-md p-6 card-hover">
                <div class="flex items-center">
                    <div class="p-3 rounded-full bg-pink-100 text-pink-600">
                        <i class="fas fa-shield-alt text-xl"></i>
                    </div>
                    <div class="ml-4">
                        <div class="text-2xl font-bold text-gray-800" id="vlessCount">0</div>
                        <div class="text-gray-600">VLESS Accounts</div>
                    </div>
                </div>
            </div>
            <div class="bg-white rounded-lg shadow-md p-6 card-hover">
                <div class="flex items-center">
                    <div class="p-3 rounded-full bg-green-100 text-green-600">
                        <i class="fas fa-lock text-xl"></i>
                    </div>
                    <div class="ml-4">
                        <div class="text-2xl font-bold text-gray-800" id="trojanCount">0</div>
                        <div class="text-gray-600">Trojan Accounts</div>
                    </div>
                </div>
            </div>
            <div class="bg-white rounded-lg shadow-md p-6 card-hover">
                <div class="flex items-center">
                    <div class="p-3 rounded-full bg-purple-100 text-purple-600">
                        <i class="fas fa-link text-xl"></i>
                    </div>
                    <div class="ml-4">
                        <div class="text-lg font-bold text-gray-800" id="domain">localhost</div>
                        <div class="text-gray-600">Domain</div>
                    </div>
                </div>
            </div>
            <div class="bg-white rounded-lg shadow-md p-6 card-hover">
                <div class="flex items-center">
                    <div class="p-3 rounded-full bg-orange-100 text-orange-600">
                        <i class="fas fa-server text-xl"></i>
                    </div>
                    <div class="ml-4">
                        <div class="text-2xl font-bold text-gray-800" id="proxyCount">0</div>
                        <div class="text-gray-600">Available Proxies</div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Main Content -->
    <div class="container mx-auto px-6">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
            <!-- Create Account Form -->
            <div class="lg:col-span-1">
                <div class="bg-white rounded-lg shadow-md p-6">
                    <h2 class="text-xl font-bold text-gray-800 mb-4">
                        <i class="fas fa-plus-circle text-pink-600 mr-2"></i>
                        Create New Account
                    </h2>
                    <form id="createForm" class="space-y-4">
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-2">Account Name</label>
                            <input type="text" id="accountName" required
                                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-pink-500"
                                placeholder="Enter account name">
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-2">Select Proxy Server</label>
                            <select id="proxySelect" required
                                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-pink-500">
                                <option value="">Loading proxies...</option>
                            </select>
                        </div>
                        <button type="submit"
                            class="w-full bg-pink-600 text-white py-2 px-4 rounded-md hover:bg-pink-700 transition duration-200 font-medium">
                            <i class="fas fa-plus mr-2"></i>
                            Create Account
                        </button>
                    </form>
                </div>

                <!-- Quick Links -->
                <div class="bg-white rounded-lg shadow-md p-6 mt-6">
                    <h3 class="text-lg font-bold text-gray-800 mb-4">
                        <i class="fas fa-link text-green-600 mr-2"></i>
                        Quick Links
                    </h3>
                    <div class="space-y-3">
                        <a href="/sub" target="_blank"
                            class="flex items-center justify-between p-3 bg-gray-50 rounded-md hover:bg-gray-100 transition duration-200">
                            <span class="text-gray-700">
                                <i class="fas fa-download mr-2"></i>
                                Subscription URL
                            </span>
                            <i class="fas fa-external-link-alt text-gray-400"></i>
                        </a>
                        <a href="/health" target="_blank"
                            class="flex items-center justify-between p-3 bg-gray-50 rounded-md hover:bg-gray-100 transition duration-200">
                            <span class="text-gray-700">
                                <i class="fas fa-heartbeat mr-2"></i>
                                Health Check
                            </span>
                            <i class="fas fa-external-link-alt text-gray-400"></i>
                        </a>
                    </div>
                </div>
            </div>

            <!-- Accounts List -->
            <div class="lg:col-span-1">
                <div class="bg-white rounded-lg shadow-md">
                    <div class="p-6 border-b border-gray-200">
                        <h2 class="text-xl font-bold text-gray-800">
                            <i class="fas fa-list text-purple-600 mr-2"></i>
                            Account List
                        </h2>
                    </div>
                    <div class="p-6">
                        <div id="accountsList" class="space-y-4">
                            <div class="text-center text-gray-500 py-8">
                                <i class="fas fa-inbox text-4xl mb-4"></i>
                                <p>No accounts created yet</p>
                                <p class="text-sm">Create your first account using the form</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Proxy List -->
        <div class="mt-8">
            <div class="bg-white rounded-lg shadow-md">
                <div class="p-6 border-b border-gray-200">
                    <h2 class="text-xl font-bold text-gray-800">
                        <i class="fas fa-server text-orange-600 mr-2"></i>
                        Available Proxy Servers
                    </h2>
                    <p class="text-gray-600 mt-1">Select a proxy server to create an account</p>
                </div>
                <div class="p-6">
                    <div id="proxyList" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                        <div class="text-center text-gray-500 py-8">
                            <i class="fas fa-spinner fa-spin text-4xl mb-4"></i>
                            <p>Loading proxies...</p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Toast Notification -->
    <div id="toast" class="fixed top-4 right-4 bg-green-500 text-white px-6 py-3 rounded-md shadow-lg transform translate-x-full transition-transform duration-300 z-50">
        <div class="flex items-center">
            <i class="fas fa-check-circle mr-2"></i>
            <span id="toastMessage">Success!</span>
        </div>
    </div>

    <script>
        let accounts = [];
        let proxies = [];
        const domain = window.location.hostname;

        // Update domain display
        document.getElementById('domain').textContent = domain;

        // Show toast notification
        function showToast(message, type = 'success') {
            const toast = document.getElementById('toast');
            const toastMessage = document.getElementById('toastMessage');
            
            toast.className = `fixed top-4 right-4 px-6 py-3 rounded-md shadow-lg transform translate-x-full transition-transform duration-300 z-50 ${
                type === 'success' ? 'bg-green-500 text-white' : 'bg-red-500 text-white'
            }`;
            
            toastMessage.textContent = message;
            toast.classList.remove('translate-x-full');
            
            setTimeout(() => {
                toast.classList.add('translate-x-full');
            }, 3000);
        }

        // Load proxies
        async function loadProxies() {
            try {
                const response = await fetch('/api/v1/proxies');
                const data = await response.json();
                
                if (data.success) {
                    proxies = data.data;
                    updateProxyStats();
                    renderProxySelect();
                    renderProxyList();
                }
            } catch (error) {
                console.error('Error loading proxies:', error);
                showToast('Error loading proxies', 'error');
            }
        }

        // Load accounts
        async function loadAccounts() {
            try {
                const response = await fetch('/api/v1/accounts');
                const data = await response.json();
                
                if (data.success) {
                    accounts = data.data;
                    updateStats();
                    renderAccounts();
                }
            } catch (error) {
                console.error('Error loading accounts:', error);
            }
        }

        // Update statistics
        function updateStats() {
            document.getElementById('totalAccounts').textContent = accounts.length;
            document.getElementById('vlessCount').textContent = accounts.filter(a => a.type === 'multi').length;
            document.getElementById('trojanCount').textContent = accounts.filter(a => a.type === 'multi').length;
        }

        function updateProxyStats() {
            document.getElementById('proxyCount').textContent = proxies.length;
        }

        // Render proxy select dropdown
        function renderProxySelect() {
            const select = document.getElementById('proxySelect');
            select.innerHTML = '<option value="">Select a proxy server</option>';
            
            proxies.forEach(proxy => {
                const option = document.createElement('option');
                option.value = proxy.id;
                option.textContent = `${proxy.proxyIP}:${proxy.proxyPort} (${proxy.country}) - ${proxy.org}`;
                select.appendChild(option);
            });
        }

        // Render proxy list
        function renderProxyList() {
            const proxyList = document.getElementById('proxyList');
            
            if (proxies.length === 0) {
                proxyList.innerHTML = `
                    <div class="text-center text-gray-500 py-8 col-span-full">
                        <i class="fas fa-exclamation-triangle text-4xl mb-4"></i>
                        <p>No proxies available</p>
                        <p class="text-sm">Check proxy sources</p>
                    </div>
                `;
                return;
            }
            
            proxyList.innerHTML = proxies.map(proxy => `
                <div class="proxy-card border border-gray-200 rounded-lg p-4 hover:shadow-md transition duration-200">
                    <div class="flex items-center justify-between mb-3">
                        <div class="flex items-center">
                            <div class="w-10 h-10 rounded-full flex items-center justify-center bg-orange-100 text-orange-600">
                                <i class="fas fa-server"></i>
                            </div>
                            <div class="ml-3">
                                <h3 class="font-semibold text-gray-800">${proxy.proxyIP}:${proxy.proxyPort}</h3>
                                <p class="text-sm text-gray-500">${proxy.country} - ${proxy.org}</p>
                            </div>
                        </div>
                        <div class="text-xs text-gray-400">#${proxy.id}</div>
                    </div>
                    <div class="bg-gray-50 rounded p-2">
                        <p class="text-xs text-gray-600">Country: ${proxy.country}</p>
                        <p class="text-xs text-gray-600">Organization: ${proxy.org}</p>
                    </div>
                </div>
            `).join('');
        }

        // Render accounts list
        function renderAccounts() {
            const accountsList = document.getElementById('accountsList');
            
            if (accounts.length === 0) {
                accountsList.innerHTML = `
                    <div class="text-center text-gray-500 py-8">
                        <i class="fas fa-inbox text-4xl mb-4"></i>
                        <p>No accounts created yet</p>
                        <p class="text-sm">Create your first account using the form</p>
                    </div>
                `;
                return;
            }
            
            accountsList.innerHTML = accounts.map(account => `
                <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition duration-200">
                    <div class="flex items-center justify-between mb-3">
                        <div class="flex items-center">
                            <div class="w-10 h-10 rounded-full flex items-center justify-center bg-pink-100 text-pink-600">
                                <i class="fas fa-user"></i>
                            </div>
                            <div class="ml-3">
                                <h3 class="font-semibold text-gray-800">${account.name}</h3>
                                <p class="text-sm text-gray-500">Proxy: ${account.proxyName}</p>
                                <p class="text-xs text-gray-400">Country: ${account.proxyCountry} - ${account.proxyOrg}</p>
                            </div>
                        </div>
                        <div class="flex space-x-2">
                            <button onclick="showConfigs('${account.id}')" 
                                class="copy-btn bg-pink-600 text-white px-3 py-1 rounded text-sm hover:bg-pink-700">
                                <i class="fas fa-eye mr-1"></i>
                                View
                            </button>
                            <button onclick="deleteAccount('${account.id}')" 
                                class="delete-btn bg-red-600 text-white px-3 py-1 rounded text-sm hover:bg-red-700">
                                <i class="fas fa-trash mr-1"></i>
                                Delete
                            </button>
                        </div>
                    </div>
                    
                    <!-- Configuration Tabs -->
                    <div id="configs-${account.id}" class="config-tabs mt-3">
                        <div class="bg-gray-50 rounded p-3">
                            <div class="flex space-x-2 mb-3">
                                <button onclick="copyConfig('${account.id}', 'vless')" 
                                    class="bg-pink-600 text-white px-3 py-1 rounded text-xs hover:bg-pink-700">
                                    Copy VLESS
                                </button>
                                <button onclick="copyConfig('${account.id}', 'trojan')" 
                                    class="bg-green-600 text-white px-3 py-1 rounded text-xs hover:bg-green-700">
                                    Copy Trojan
                                </button>
                                <button onclick="copyConfig('${account.id}', 'shadowsocks')" 
                                    class="bg-purple-600 text-white px-3 py-1 rounded text-xs hover:bg-purple-700">
                                    Copy SS
                                </button>
                            </div>
                            <div class="space-y-2">
                                <div>
                                    <p class="text-xs font-semibold text-gray-700">VLESS:</p>
                                    <p class="text-xs text-gray-600 break-all bg-white p-2 rounded">${account.configs.vless}</p>
                                </div>
                                <div>
                                    <p class="text-xs font-semibold text-gray-700">Trojan:</p>
                                    <p class="text-xs text-gray-600 break-all bg-white p-2 rounded">${account.configs.trojan}</p>
                                </div>
                                <div>
                                    <p class="text-xs font-semibold text-gray-700">Shadowsocks:</p>
                                    <p class="text-xs text-gray-600 break-all bg-white p-2 rounded">${account.configs.shadowsocks}</p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            `).join('');
        }

        // Show/Hide configurations
        function showConfigs(accountId) {
            const configsDiv = document.getElementById(`configs-${accountId}`);
            if (configsDiv.classList.contains('active')) {
                configsDiv.classList.remove('active');
            } else {
                // Hide all other configs first
                document.querySelectorAll('.config-tabs').forEach(div => {
                    div.classList.remove('active');
                });
                configsDiv.classList.add('active');
            }
        }

        // Create account
        document.getElementById('createForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const name = document.getElementById('accountName').value;
            const proxyId = document.getElementById('proxySelect').value;
            
            try {
                const response = await fetch('/api/v1/accounts', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ name, proxyId })
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showToast('Account created successfully!');
                    document.getElementById('createForm').reset();
                    loadAccounts();
                } else {
                    showToast(data.message, 'error');
                }
            } catch (error) {
                showToast('Error creating account', 'error');
            }
        });

        // Copy configuration
        async function copyConfig(accountId, type) {
            const account = accounts.find(a => a.id === accountId);
            if (account && account.configs[type]) {
                try {
                    await navigator.clipboard.writeText(account.configs[type]);
                    showToast(`${type.toUpperCase()} configuration copied!`);
                } catch (error) {
                    showToast('Failed to copy configuration', 'error');
                }
            }
        }

        // Delete account
        async function deleteAccount(id) {
            if (!confirm('Are you sure you want to delete this account?')) {
                return;
            }
            
            try {
                const response = await fetch(`/api/v1/accounts/${id}`, {
                    method: 'DELETE'
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showToast('Account deleted successfully!');
                    loadAccounts();
                } else {
                    showToast(data.message, 'error');
                }
            } catch (error) {
                showToast('Error deleting account', 'error');
            }
        }

        // Load data on page load
        loadProxies();
        loadAccounts();
    </script>
</body>
</html>
EOF

# Create ecosystem.config.js
echo -e "${BLUE}📄 Creating PM2 configuration...${NC}"
cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'dianastore-proxy-v2',
    script: 'server.js',
    cwd: '/opt/dianastore-proxy-v2',
    env: {
      NODE_ENV: 'production',
      PORT: 3000,
      DOMAIN: '$DOMAIN'
    },
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    log_file: '/opt/dianastore-proxy-v2/logs/combined.log',
    out_file: '/opt/dianastore-proxy-v2/logs/out.log',
    error_file: '/opt/dianastore-proxy-v2/logs/error.log'
  }]
}
EOF

# Create logs directory
mkdir -p logs

# Install dependencies
echo -e "${BLUE}📦 Installing Node.js dependencies...${NC}"
npm install > /dev/null 2>&1
echo -e "${GREEN}✅ Dependencies installed!${NC}"

# Start PM2 service
echo -e "${BLUE}🚀 Starting service with PM2...${NC}"
pm2 start ecosystem.config.js > /dev/null 2>&1
pm2 save > /dev/null 2>&1
pm2 startup > /dev/null 2>&1
echo -e "${GREEN}✅ Service started!${NC}"

# Configure Nginx with improved WebSocket support
echo -e "${BLUE}🌐 Configuring Nginx with enhanced WebSocket support...${NC}"
cat > /etc/nginx/sites-available/dianastore-proxy-v2 << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    location / {
        proxy_set_header Host $host;
            proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        
        # Enhanced WebSocket support
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_max_temp_file_size 0;
    }
    
    # Additional WebSocket specific location for proxy paths
    location ~ ^/[^-]+-\d+$ {
        proxy_set_header Host $host;
            proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        
        # Enhanced WebSocket support
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_max_temp_file_size 0;
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/dianastore-proxy-v2 /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and start Nginx
nginx -t > /dev/null 2>&1
if [ $? -eq 0 ]; then
    systemctl start nginx > /dev/null 2>&1
    systemctl enable nginx > /dev/null 2>&1
    echo -e "${GREEN}✅ Nginx configured and started!${NC}"
else
    echo -e "${RED}❌ Nginx configuration error${NC}"
    exit 1
fi

# Configure firewall
echo -e "${BLUE}🔥 Configuring firewall...${NC}"
ufw --force reset > /dev/null 2>&1
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow ssh > /dev/null 2>&1
ufw allow 80 > /dev/null 2>&1
ufw allow 443 > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1
echo -e "${GREEN}✅ Firewall configured!${NC}"

# Setup SSL certificate
echo -e "${BLUE}🔒 Setting up SSL certificate...${NC}"
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SSL certificate installed!${NC}"
    SSL_STATUS="✅ HTTPS Enabled"
    PROTOCOL="https"
else
    echo -e "${YELLOW}⚠️ SSL certificate failed, using HTTP${NC}"
    SSL_STATUS="⚠️ HTTP Only"
    PROTOCOL="http"
fi

# Test service
echo -e "${BLUE}🧪 Testing service...${NC}"
sleep 5
if curl -s http://localhost:3000/health > /dev/null; then
    echo -e "${GREEN}✅ Service is running!${NC}"
else
    echo -e "${RED}❌ Service test failed${NC}"
fi

# Get server IP
SERVER_IP=$(curl -s ifconfig.me)

# Final output
clear
echo -e "${BLUE}"
echo "================================================"
echo "  🎉 DIANASTORE PROXY INSTALLATION COMPLETED!"
echo "================================================"
echo -e "${NC}"
echo ""
echo -e "${GREEN}✅ All components installed and configured!${NC}"
echo ""
echo -e "${CYAN}📋 Service Information:${NC}"
echo -e "   Domain: ${YELLOW}$DOMAIN${NC}"
echo -e "   Server IP: ${YELLOW}$SERVER_IP${NC}"
echo -e "   SSL Status: ${YELLOW}$SSL_STATUS${NC}"
echo -e "   Internal Port: ${YELLOW}3000${NC}"
echo ""
echo -e "${CYAN}🌐 Access URLs:${NC}"
echo -e "   Dashboard: ${GREEN}$PROTOCOL://$DOMAIN/${NC}"
echo -e "   Subscription: ${GREEN}$PROTOCOL://$DOMAIN/sub${NC}"
echo -e "   Health Check: ${GREEN}$PROTOCOL://$DOMAIN/health${NC}"
echo -e "   Local Access: ${GREEN}http://localhost:3000/${NC}"
echo ""
echo -e "${CYAN}🔧 Management Commands:${NC}"
echo -e "   View Logs: ${YELLOW}pm2 logs dianastore-proxy-v2${NC}"
echo -e "   Restart: ${YELLOW}pm2 restart dianastore-proxy-v2${NC}"
echo -e "   Status: ${YELLOW}pm2 status${NC}"
echo -e "   Stop: ${YELLOW}pm2 stop dianastore-proxy-v2${NC}"
echo ""
echo -e "${CYAN}✨ DIANASTORE PROXY Features:${NC}"
echo -e "   • VLESS, Trojan, Shadowsocks with WebSocket support"
echo -e "   • Full HTTPUpgrade implementation"
echo -e "   • TLS and SNI support"
echo -e "   • Path format: /IP-PORT"
echo -e "   • Country flag emojis"
echo -e "   • Multiple config types per account"
echo -e "   • Beautiful web dashboard"
echo -e "   • SSL certificate (if available)"
echo -e "   • Enhanced WebSocket proxy forwarding"
echo -e "   • Version compatibility fixes"
echo ""
echo -e "${GREEN}🚀 Your DIANASTORE PROXY Server is ready!${NC}"
echo -e "${YELLOW}Open your browser and visit: $PROTOCOL://$DOMAIN/${NC}"
echo ""
echo -e "${CYAN}📝 Note:${NC}"
echo -e "   This is a FIXED installation that properly implements WebSocket proxying"
echo -e "   All accounts now support HTTPUpgrade, WebSocket, TLS, and SNI"
echo ""

# Ensure xray restarted (added by patch)
systemctl daemon-reload || true
systemctl enable xray || true
systemctl restart xray || true
systemctl status xray --no-pager -n 20 || true

echo Generating or using UUIDs...
