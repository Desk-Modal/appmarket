var c=Object.defineProperty;var l=(o,t,e)=>t in o?c(o,t,{enumerable:!0,configurable:!0,writable:!0,value:e}):o[t]=e;var s=(o,t,e)=>l(o,typeof t!="symbol"?t+"":t,e);class u extends Error{constructor(t,e){super(`GraphQL error: ${t.map(r=>r.message).join("; ")}`),this.errors=t,this.partialData=e,this.name="GraphQLError"}}const d=5,m=100,y=3e4,p="https://gateway.thegraph.com/api";class w{constructor(t){s(this,"exchangeId","the-graph");s(this,"displayName","The Graph");s(this,"category","data-provider");s(this,"capabilities",{realtime:!1,historicalDepth:"full",orderbook:!1,trades:!0,ohlcv:!1,fundingRates:!1,openInterest:!1,liquidations:!1,defiMetrics:!0,onChainMetrics:!0,authenticated:!1});s(this,"apiKey");s(this,"defaultGateway");s(this,"cache",new Map);s(this,"rateLimiter",{inflight:0,timestamps:[],waiters:[]});this.apiKey=t==null?void 0:t.apiKey,this.defaultGateway=(t==null?void 0:t.defaultGateway)??p}getHealthMetrics(){return{connected:!0,latencyMs:0,messagesPerSecond:0,uptimePercent:100,lastMessageAt:0,errorRate:0,circuitBreakerState:"closed"}}async query(t,e,r){const a=this.computeCacheKey(t,e,r),i=this.getCached(a);if(i!==void 0)return i;await this.acquireRateLimit();try{const h=await fetch(t,{method:"POST",headers:{"Content-Type":"application/json",...this.apiKey?{Authorization:`Bearer ${this.apiKey}`}:{}},body:JSON.stringify({query:e,...r!==void 0?{variables:r}:{}})});if(!h.ok)throw new Error(`HTTP ${h.status}: ${h.statusText}`);const n=await h.json();if(n.errors&&n.errors.length>0)throw new u(n.errors,n.data);if(n.data===void 0)throw new Error("GraphQL response missing data field");return this.setCache(a,n.data),n.data}finally{this.releaseRateLimit()}}async getUniswapV3Pools(t,e){const r=(e==null?void 0:e.first)??100,a=(e==null?void 0:e.orderBy)??"totalValueLockedUSD";return(await this.query(t,`
      query GetPools($first: Int!, $orderBy: String!) {
        pools(first: $first, orderBy: $orderBy, orderDirection: desc) {
          id
          token0 { id symbol decimals }
          token1 { id symbol decimals }
          feeTier
          totalValueLockedUSD
          volumeUSD
          txCount
        }
      }
    `,{first:r,orderBy:a})).pools}async getTokenDayData(t,e,r=30){const a=Math.floor(Date.now()/1e3)-r*86400;return(await this.query(t,`
      query GetTokenDayData($tokenAddress: String!, $cutoff: Int!) {
        tokenDayDatas(
          where: { token: $tokenAddress, date_gt: $cutoff }
          orderBy: date
          orderDirection: desc
          first: 1000
        ) {
          date
          priceUSD
          totalValueLockedUSD
          volume
        }
      }
    `,{tokenAddress:e.toLowerCase(),cutoff:a})).tokenDayDatas}async getProtocolMetrics(t){var i;const a=(i=(await this.query(t,`
      query GetProtocolMetrics {
        factories(first: 1) {
          totalValueLockedUSD
          totalVolumeUSD
          txCount
        }
      }
    `)).factories)==null?void 0:i[0];if(!a)throw new Error("No factory data found in subgraph");return a}buildSubgraphUrl(t){if(!this.apiKey)throw new Error("API key required to build gateway subgraph URL");return`${this.defaultGateway}/${this.apiKey}/subgraphs/id/${t}`}clearCache(){this.cache.clear()}computeCacheKey(t,e,r){const a=e.replace(/\s+/g," ").trim(),i=r!==void 0?JSON.stringify(r):"";return`${t}|${a}|${i}`}getCached(t){const e=this.cache.get(t);if(e){if(Date.now()>e.expiresAt){this.cache.delete(t);return}return e.data}}setCache(t,e){this.cache.set(t,{data:e,expiresAt:Date.now()+y})}async acquireRateLimit(){const e=Date.now()-6e4;for(;this.rateLimiter.timestamps.length>0&&(this.rateLimiter.timestamps[0]??0)<e;)this.rateLimiter.timestamps.shift();for(;this.rateLimiter.inflight>=d||this.rateLimiter.timestamps.length>=m;){await new Promise(i=>{this.rateLimiter.waiters.push(i)});const a=Date.now()-6e4;for(;this.rateLimiter.timestamps.length>0&&(this.rateLimiter.timestamps[0]??0)<a;)this.rateLimiter.timestamps.shift()}this.rateLimiter.inflight++,this.rateLimiter.timestamps.push(Date.now())}releaseRateLimit(){if(this.rateLimiter.inflight--,this.rateLimiter.waiters.length>0){const t=this.rateLimiter.waiters.shift();t&&t()}}}export{u as GraphQLError,w as TheGraphAdapter};
//# sourceMappingURL=the-graph-adapter-eWB9ljJ8.js.map
