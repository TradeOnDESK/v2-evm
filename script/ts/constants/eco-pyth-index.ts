import { ethers } from "ethers";

// DO NOT CHANGE THE ORDER OF THE INDEXES
export const ecoPythPriceFeedIdsByIndex = [
  "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace", // ETHUSD
  "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43", // BTCUSD
  "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a", // USDCUSD
  "0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b", // USDTUSD
  "0xb0948a5e5313200c632b51bb5ca32f6de0d36e9950a942d19751e833f70dabfd", // DAIUSD
  "0x49f6b65cb1de6b10eaf75e7c03ca029c306d0357e91b5311b175084a5ad55688", // AAPLUSD
  "0xef2c98c804ba503c6a707e38be4dfbb16683775f195b091252bf24693042fd52", // JPYUSD
  "0x765d2ba906dbc32ca17cc11f5310a89e9ee1f6420508c63861f2f8ba4ee34bb2", // XAUUSD
  "0xb5d0e0fa58a1f8b81498ae670ce93c872d14434b72c364885d4fa1b257cbb07a", // AMZNUSD
  "0xd0ca23c1cc005e004ccf1db5bf76aeb6a49218f43dac3d4b275e92de12ded4d1", // MSFTUSD
  "0x16dad506d7db8da01c87581c87ca897a012a153557d4d578c3b9c9e1bc0632f1", // TSLAUSD
  "0xa995d00bb36a63cef7fd2c287dc105fc8f3d93779f062f09551b0af3e81ec30b", // EURUSD
  "0xf2fb02c32b055c805e7238d628e5e9dadef274376114eb1f012337cabe93871e", // XAGUSD
  "GLP", // GLP
  "0x67a6f93030420c1c9e3fe37c1ab6b77966af82f995944a9fefce357a22854a80", // AUDUSD
  "0x84c2dde9633d93d1bcad84e7dc41c9d56578b7ec52fabedc1f335d673df0a7c1", // GBPUSD
  "0x2a01deaec9e51a579277b34b122399984d0bbf57e2458a7e42fecd2829867a0d", // ADAUSD
  "0xffd11c5a1cfd42f80afb2df4d9f264c15f956d68153335374ec10722edd70472", // POLUSD
  "0x23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744", // SUIUSD
  "0x3fa4252848f9f0a1480be62745a4629d9eb1322aebab8a791e344b3b9c1adcf5", // ARBUSD
  "0x385f64d993f7b77d8182ed5003d97c60aa3361f3cecfe711544d2d59165e9bdf", // OPUSD
  "0x6e3f3fa8253588df9326580180233eb791e03b443a3ba7a1d892e73874e19a54", // LTCUSD
  "0xfee33f2a978bf32dd6b662b65ba8083c6773b494f8401194ec1870c640860245", // COINUSD
  "0xe65ff435be42630439c96396653a342829e877e2aafaeaf1a10d0ee5fd2cf3f2", // GOOGUSD
  "0x2f95862b045670cd22bee3114c39763a4a08beeb663b145d283c31d7d1101c4f", // BNBUSD
  "0xef0d8b6fda2ceba41da15d4095d1da392a0d2f8ed0c6c7bc0f4cfac8c280b56d", // SOLUSD
  "0x9695e2b96ea7b3859da9ed25b7a46a920a776e2fdae19a7bcfdf2b219230452d", // QQQUSD
  "0xec5d399846a9209f3fe5881d70aae9268c94339ff9817e8d18ff19fa05eea1c8", // XRPUSD
  "0xb1073854ed24cbc755dc527418f52b7d271f6cc967bbf8d8129112b18860a593", // NVDAUSD
  "0x8ac0c70fff57e9aefdf5edf44b51d62c2d433653cbb2cf5cc06bb115af04d221", // LINKUSD
  "0x0b1e3297e69f162877b577b0d6a47a0d63b2392bc8499e6540da4187a63e28f8", // USDCHF
  "0xdcef50dd0a4cd2dcc17e45df1676dcb336a11a61c69df7a0299b0150c672d25c", // DOGEUSD
  "0x3112b03a41c910ed446852aacf67118cb1bec67b2cd0b9a214c58cc0eaa2ecca", // USDCAD
  "0x396a969a9c1480fa15ed50bc59149e2c0075a72fe8f458ed941ddec48bdb4918", // USDSGD
  "wstETH",
  "0xeef52e09c878ad41f6a81803e3640fe04dceea727de894edd4ea117e2e332e66", // USDCNH
  "0x19d75fde7fee50fe67753fdc825e583594eb2f51ae84e114a5246c4ab23aff4c", // USDHKD
  "0x3dd2b63686a450ec7290df3a1e0b583c0481f651351edfa7636f39aed55cf8a3", // BCHUSD
  "0xcd2cee36951a571e035db0dfad138e6ecdb06b517cc3373cd7db5d3609b7927c", // MEMEUSD
  "GM-BTCUSD",
  "GM-ETHUSD",
  "0x8ccb376aa871517e807358d4e3cf0bc7fe4950474dbe6c9ffc21ef64e43fc676", // USDSEK
  "DIX",
  "0xb43660a5f790c69354b0729a5ef9d50d68f1df92107540210b9cccba1f947cc2", // JTOUSD
  "0xec7a775f46379b5e943c3526b1c8d54cd49749176b0b98e02dde68d1bd335c17", // STXUSD
  "0x193c739db502aadcef37c2589738b1e37bdb257d58cf1ab3c7ebc8e6df4e3ec0", // ORDIUSD
  "0x09f7c1d7dfbb7df2b8fe3d3d87ee94a2259d212da4f30c1f0540d066dfa44723", // TIAUSD
  "0x93da3352f9f1d105fdfe4971cfa80e9dd777bfc5d0f683ebb6e1294b92137bb7", // AVAXUSD
  "0x7a5bc1d2b56ad029048cd63964b3ad2776eadf812edc1a43a31406cb54bff592", // INJUSD
  "0xca3eed9b267293f6595901c734c7525ce8ef49adafe8284606ceb307afa2ca5b", // DOTUSD
  "0x53614f1cb0c031d4af66c04cb9c756234adad0e1cee85303795091499a4084eb", // SEIUSD
  "0xb00b60f88b03a6a625a8d1c048c3f66653edf217439983d037e7222c4e612819", // ATOMUSD
  "0xd69731a2e74ac1ce884fc3890f7ee324b6deb66147055249568869ed700882e4", // PEPEUSD
  "0xf0d57deca57b3da2fe63a493f4c25925fdfd8edf834b20f93e1f84dbd1504d4a", // SHIBUSD
  "0xc9907d786c5821547777780a1e4f89484f3417cb14dd244f2b0a34ea7a554d67", // ICPUSD
  "0xc3883bcf1101c111e9fcfe2465703c47f2b638e21fef2cce0502e6c8f416e0e2", // MANTAUSD
  "0x6a182399ff70ccf3e06024898942028204125a819e519a335ffa4579e66cd870", // STRKUSD,
  "0x0bbf28e9a841a1cc788f6a361b17ca072d0ea3098a1e5df1c3922d06719579ff", // PYTHUSD
  "0x9a4df90b25497f66b1afb012467e316e801ca3d839456db028892fe8c70c8016", // PENDLEUSD
  "0xeff7446475e218517566ea99e72a4abec2e1bd8498b43b7d8331e29dcb059389", // WUSD
  "0xb7910ba7322db020416fcac28b48c01212fd9cc8fbcbaf7d30477ed8605f6bd4", // ENAUSD
  "WUSDM",
  "0xeca3fb7e6be5be55a01678ee00f6405b9e4986e32d539ccd2a06a57e0c615880", // WTI1M
  "0x92b8527aabe59ea2b12230f7b532769b133ffb118dfbd48ff676f14b273f1365", // CRCL
];
export const ecoPythAssetIdByIndex = [
  "0x4554480000000000000000000000000000000000000000000000000000000000", // ETH
  "0x4254430000000000000000000000000000000000000000000000000000000000", // BTC
  "0x5553444300000000000000000000000000000000000000000000000000000000", // USDC
  "0x5553445400000000000000000000000000000000000000000000000000000000", // USDT
  "0x4441490000000000000000000000000000000000000000000000000000000000", // DAI
  "0x4141504c00000000000000000000000000000000000000000000000000000000", // AAPL
  "0x4a50590000000000000000000000000000000000000000000000000000000000", // JPY
  "0x5841550000000000000000000000000000000000000000000000000000000000", // XAU
  "0x414d5a4e00000000000000000000000000000000000000000000000000000000", // AMZN
  "0x4d53465400000000000000000000000000000000000000000000000000000000", // MSFT
  "0x54534c4100000000000000000000000000000000000000000000000000000000", // TSLA
  "0x4555520000000000000000000000000000000000000000000000000000000000", // EUR
  "0x5841470000000000000000000000000000000000000000000000000000000000", // XAG
  "0x474c500000000000000000000000000000000000000000000000000000000000", // GLP
  ethers.utils.formatBytes32String("AUD"),
  ethers.utils.formatBytes32String("GBP"),
  ethers.utils.formatBytes32String("ADA"),
  ethers.utils.formatBytes32String("MATIC"),
  ethers.utils.formatBytes32String("SUI"),
  ethers.utils.formatBytes32String("ARB"),
  ethers.utils.formatBytes32String("OP"),
  ethers.utils.formatBytes32String("LTC"),
  ethers.utils.formatBytes32String("COIN"),
  ethers.utils.formatBytes32String("GOOG"),
  ethers.utils.formatBytes32String("BNB"),
  ethers.utils.formatBytes32String("SOL"),
  ethers.utils.formatBytes32String("QQQ"),
  ethers.utils.formatBytes32String("XRP"),
  ethers.utils.formatBytes32String("NVDA"),
  ethers.utils.formatBytes32String("LINK"),
  ethers.utils.formatBytes32String("CHF"),
  ethers.utils.formatBytes32String("DOGE"),
  ethers.utils.formatBytes32String("CAD"),
  ethers.utils.formatBytes32String("SGD"),
  ethers.utils.formatBytes32String("wstETH"),
  ethers.utils.formatBytes32String("CNH"),
  ethers.utils.formatBytes32String("HKD"),
  ethers.utils.formatBytes32String("BCH"),
  ethers.utils.formatBytes32String("MEME"),
  ethers.utils.formatBytes32String("GM-BTCUSD"),
  ethers.utils.formatBytes32String("GM-ETHUSD"),
  ethers.utils.formatBytes32String("SEK"),
  ethers.utils.formatBytes32String("DIX"),
  ethers.utils.formatBytes32String("JTO"),
  ethers.utils.formatBytes32String("STX"),
  ethers.utils.formatBytes32String("ORDI"),
  ethers.utils.formatBytes32String("TIA"),
  ethers.utils.formatBytes32String("AVAX"),
  ethers.utils.formatBytes32String("INJ"),
  ethers.utils.formatBytes32String("DOT"),
  ethers.utils.formatBytes32String("SEI"),
  ethers.utils.formatBytes32String("ATOM"),
  ethers.utils.formatBytes32String("1000PEPE"),
  ethers.utils.formatBytes32String("1000SHIB"),
  ethers.utils.formatBytes32String("ICP"),
  ethers.utils.formatBytes32String("MANTA"),
  ethers.utils.formatBytes32String("STRK"),
  ethers.utils.formatBytes32String("PYTH"),
  ethers.utils.formatBytes32String("PENDLE"),
  ethers.utils.formatBytes32String("W"),
  ethers.utils.formatBytes32String("ENA"),
  ethers.utils.formatBytes32String("WUSDM"),
  ethers.utils.formatBytes32String("WTI1M"),
  ethers.utils.formatBytes32String("CRCL"),
];
export const ecoPythHoomanReadableByIndex = [
  "ETH",
  "BTC",
  "USDC",
  "USDT",
  "DAI",
  "AAPL",
  "JPY",
  "XAU",
  "AMZN",
  "MSFT",
  "TSLA",
  "EUR",
  "XAG",
  "GLP",
  "AUD",
  "GBP",
  "ADA",
  "MATIC",
  "SUI",
  "ARB",
  "OP",
  "LTC",
  "COIN",
  "GOOG",
  "BNB",
  "SOL",
  "QQQ",
  "XRP",
  "NVDA",
  "LINK",
  "CHF",
  "DOGE",
  "CAD",
  "SGD",
  "wstETH",
  "CNH",
  "HKD",
  "BCH",
  "MEME",
  "GM-BTCUSD",
  "GM-ETHUSD",
  "SEK",
  "DIX",
  "JTO",
  "STX",
  "ORDI",
  "TIA",
  "AVAX",
  "INJ",
  "DOT",
  "SEI",
  "ATOM",
  "1000PEPE",
  "1000SHIB",
  "ICP",
  "MANTA",
  "STRK",
  "PYTH",
  "PENDLE",
  "W",
  "ENA",
  "WUSDM",
  "WTI1M",
  "CRCL",
];
export const multiplicationFactorMapByAssetId: Map<string, number> = new Map([
  [ethers.utils.formatBytes32String("1000SHIB"), 1000],
  [ethers.utils.formatBytes32String("1000PEPE"), 1000],
]);
