var S=Object.defineProperty;var g=(n,t,e)=>t in n?S(n,t,{enumerable:!0,configurable:!0,writable:!0,value:e}):n[t]=e;var i=(n,t,e)=>g(n,typeof t!="symbol"?t+"":t,e);import{c as h,p as o,a as b}from"./index-rDma_jNS.js";import{R as y,E as f}from"./rate-limiter-DgX5XWMZ.js";function w(n,t,e){const r=typeof n=="string"?BigInt(n):n,s=2n**96n,c=r*r*10n**BigInt(t),a=s*s*10n**BigInt(e);return a===0n?0:Number(c)/Number(a)}const k="https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3",M=15e3;class v{constructor(){i(this,"exchangeId","uniswap-v3");i(this,"displayName","Uniswap V3");i(this,"category","dex");i(this,"capabilities",{realtime:!0,historicalDepth:"30d",orderbook:!1,trades:!0,ohlcv:!0,fundingRates:!1,openInterest:!1,liquidations:!1,defiMetrics:!0,onChainMetrics:!0,authenticated:!1});i(this,"config",null);i(this,"subgraphUrl",k);i(this,"rateLimiter",null);i(this,"subscriptions",new Map);i(this,"statusCallbacks",new Map);i(this,"pollTimer");i(this,"pollIntervalMs",M);i(this,"connectionState",{state:"disconnected",latencyMs:0,messagesPerSecond:0,lastMessageAt:0,reconnectAttempt:0,uptime:0});i(this,"connectTime",0)}async connect(t){this.config=t,t.restUrl&&(this.subgraphUrl=t.restUrl);const e=f["uniswap-v3"];e&&(this.rateLimiter=new y("uniswap-v3",e)),this.connectTime=Date.now(),this.updateState("connected"),this.pollTimer=setInterval(()=>{this.pollSubscriptions().catch(()=>{})},this.pollIntervalMs)}async disconnect(){var t;this.pollTimer!==void 0&&(clearInterval(this.pollTimer),this.pollTimer=void 0),this.subscriptions.clear(),this.statusCallbacks.clear(),(t=this.rateLimiter)==null||t.dispose(),this.rateLimiter=null,this.updateState("disconnected")}getStatus(){return{...this.connectionState,uptime:this.getUptime()}}getHealthMetrics(){const t=this.getStatus(),e=t.uptime,r=e>0?Math.min(100,e/e*100):0;return{connected:t.state==="connected",latencyMs:t.latencyMs,messagesPerSecond:t.messagesPerSecond,uptimePercent:r,lastMessageAt:t.lastMessageAt,errorRate:0,circuitBreakerState:"closed"}}onStatusChange(t){const e=h("uniswap-v3","status","_global");return this.statusCallbacks.set(e,t),{id:e,symbol:"_global",type:"status",dispose:()=>{this.statusCallbacks.delete(e)}}}subscribeTicker(t,e){return this.addSubscription(t,"ticker",e)}subscribeOrderbook(t,e,r){return this.addSubscription(t,"orderbook",r)}subscribeTrades(t,e){return this.addSubscription(t,"trades",e)}subscribeOHLCV(t,e,r){return this.addSubscription(t,"ohlcv",r)}async getCandles(t,e,r,s){var p;const c=this.extractPoolAddress(t),a=Math.floor(r/1e3),u=Math.floor(s/1e3),d=`{
      poolHourDatas(
        where: { pool: "${c}", periodStartUnix_gte: ${a}, periodStartUnix_lte: ${u} }
        orderBy: periodStartUnix
        orderDirection: asc
        first: 1000
      ) {
        periodStartUnix open high low close volumeUSD txCount
      }
    }`;return await((p=this.rateLimiter)==null?void 0:p.acquire()),(await this.executeQuery(d)).data.poolHourDatas.map(l=>({timestamp:b(l.periodStartUnix),open:o(l.open),high:o(l.high),low:o(l.low),close:o(l.close),volume:o(l.volumeUSD),quoteVolume:o(l.volumeUSD),tradeCount:o(l.txCount),closed:!0}))}async getOrderbookSnapshot(t,e){throw new Error("Order book not available for Uniswap V3 AMM pools")}async getRecentTrades(t,e){var a;const s=`{
      swaps(
        where: { pool: "${this.extractPoolAddress(t)}" }
        orderBy: timestamp
        orderDirection: desc
        first: ${Math.min(e,1e3)}
      ) {
        id timestamp amount0 amount1 sqrtPriceX96
        transaction { id }
      }
    }`;return await((a=this.rateLimiter)==null?void 0:a.acquire()),(await this.executeQuery(s)).data.swaps.map(u=>{const d=o(u.amount0),m=o(u.amount1),p=d!==0?Math.abs(m/d):0;return{id:u.id,timestamp:b(o(u.timestamp)),price:p,quantity:Math.abs(d),side:d>0?"buy":"sell",buyerMaker:!1}})}async getSymbols(){var r;const t=`{
      pools(
        first: 100
        orderBy: totalValueLockedUSD
        orderDirection: desc
        where: { totalValueLockedUSD_gt: "100000" }
      ) {
        id token0 { id symbol name decimals } token1 { id symbol name decimals }
        feeTier liquidity sqrtPrice volumeUSD totalValueLockedUSD
      }
    }`;return await((r=this.rateLimiter)==null?void 0:r.acquire()),(await this.executeQuery(t)).data.pools.map(s=>{const c=parseInt(s.token0.decimals,10),a=parseInt(s.token1.decimals,10),u=parseInt(s.feeTier,10);return{symbol:`${s.token0.symbol}/${s.token1.symbol}`,base:s.token0.symbol,quote:s.token1.symbol,exchangeSymbol:s.id,exchangeId:"uniswap-v3",type:"dex-pool",pricePrecision:Math.max(c,a),quantityPrecision:c,minQuantity:0,tickSize:w(1n,c,a),active:o(s.liquidity)>0,contractAddress:s.id,chain:"ethereum",feeTier:u}})}addSubscription(t,e,r){const s=h("uniswap-v3",e,t),c=this.extractPoolAddress(t),a={id:s,symbol:t,poolAddress:c,type:e,callback:r};return this.subscriptions.set(s,a),{id:s,symbol:t,type:e,dispose:()=>{this.subscriptions.delete(s)}}}async pollSubscriptions(){const t=Array.from(this.subscriptions.values()).filter(e=>e.type==="trades");for(const e of t){const r=await this.getRecentTrades(e.symbol,10);for(const s of r)e.callback(s)}}async executeQuery(t){const e=await fetch(this.subgraphUrl,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({query:t})});if(!e.ok)throw new Error(`The Graph query failed: ${e.status} ${e.statusText}`);const r=await e.json();if(r.errors&&r.errors.length>0){const s=r.errors[0];throw new Error(`GraphQL error: ${(s==null?void 0:s.message)??"Unknown error"}`)}return r}extractPoolAddress(t){return t.startsWith("0x"),t.toLowerCase()}updateState(t,e){this.connectionState={state:t,latencyMs:this.connectionState.latencyMs,messagesPerSecond:this.connectionState.messagesPerSecond,lastMessageAt:this.connectionState.lastMessageAt,errorMessage:e,reconnectAttempt:0,uptime:this.getUptime()};for(const r of this.statusCallbacks.values())r(this.connectionState)}getUptime(){return this.connectTime===0?0:(Date.now()-this.connectTime)/1e3}}export{v as UniswapV3Adapter};
//# sourceMappingURL=uniswap-adapter-41qI31mN.js.map
