/* ---------- advanced sales analytics ---------- */
let analyticsDays=30;
function recentDays(n) {
  const now=new Date(), list=[];
  for(let i=n-1;i>=0;i--){ const d=new Date(now.getFullYear(),now.getMonth(),now.getDate()-i);
    list.push(`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`); }
  return list;
}
function analyticsStats(orders) {
  const os=orders.filter(sold), collected=money(os.reduce((a,o)=>a+Number(o.paid||0),0));
  const sales=money(os.reduce((a,o)=>a+Number(o.total||0),0));
  const discounts=money(os.reduce((a,o)=>a+Number(o.discount||0),0));
  const cost=money(os.reduce((a,o)=>a+costOf(o),0));
  const outstanding=money(os.reduce((a,o)=>a+Math.max(0,Number(o.total||0)-Number(o.paid||0)),0));
  const counts={}; os.filter(o=>o.customerId!=null).forEach(o=>counts[o.customerId]=(counts[o.customerId]||0)+1);
  const members=Object.keys(counts).length, repeating=Object.values(counts).filter(n=>n>1).length;
  return {orders:os.length,collected,sales,discounts,cost,gross:money(sales-cost),
    aov:os.length?money(sales/os.length):0,outstanding,repeatRate:members?money(repeating/members*100):0,
    pointsIssued:os.reduce((a,o)=>a+earnedPoints(o),0),pointsRedeemed:os.reduce((a,o)=>a+(o.status==='Completed'?Number(o.redeemedPoints)||0:0),0)};
}
function sparkBars(days) {
 const max=Math.max(1,...days.map(d=>d.value));
 return `<div class="chart-bars" role="img" aria-label="Daily paid sales bar chart">${days.map(d=>`<div class="bar" style="height:${Math.max(1,(d.value/max)*98)}%" title="${esc(d.date)}: ${RM(d.value)}"></div>`).join('')}</div><div class="row mut" style="justify-content:space-between;font-size:11px"><span>${esc(days[0]?.date||'')}</span><span>${esc(days.at(-1)?.date||'')}</span></div>`;
}
function analytics() {
 const dates=recentDays(analyticsDays), first=dates[0], last=dates.at(-1);
 const all=db.orders.filter(o=>o.date>=first&&o.date<=last);
 const os=all.filter(sold), a=analyticsStats(all);
 const days=dates.map(d=>({date:d,value:money(os.filter(o=>o.date===d).reduce((sum,o)=>sum+Number(o.paid||0),0))}));
 const methods=['Cash','QR PAY'];
 const payment=methods.map(name=>({name,total:money(os.filter(o=>o.payment===name).reduce((sum,o)=>sum+Number(o.paid||0),0))}));
 const products=new Map();
 for(const o of os) for(const i of (o.items||[])){
   const key=i.name||'Unnamed product',x=products.get(key)||{name:key,qty:0,total:0};
   x.qty+=Number(i.qty)||0;x.total+=Number(i.qty||0)*Number(i.price||0);products.set(key,x);
 }
 const topProducts=[...products.values()].sort((x,y)=>y.total-x.total).slice(0,8);
 const byCustomer=new Map();
 for(const o of os.filter(o=>o.customerId!=null)){
   const key=String(o.customerId),x=byCustomer.get(key)||{name:db.customers.find(c=>String(c.id)===key)?.name||o.customer,total:0,orders:0};
   x.total+=Number(o.paid)||0;x.orders++;byCustomer.set(key,x);
 }
 const topCustomers=[...byCustomer.values()].sort((x,y)=>y.total-x.total).slice(0,8);
 const maxProd=Math.max(1,...topProducts.map(p=>p.total));
 return `<h2>Advanced Analytics</h2>
  <div class="card"><div class="row"><label>Reporting period<select onchange="analyticsDays=Number(this.value);go('analytics')">
    ${[7,30,90,365].map(n=>`<option value="${n}" ${analyticsDays===n?'selected':''}>Last ${n} days</option>`).join('')}</select></label>
    <span class="mut">${first} – ${last} · excludes cancelled sales</span>
    <button class="btn p" onclick="exportAnalytics()">Export CSV</button></div></div>
  <div class="cards"><div class="card">Collected payments<b>${RM(a.collected)}</b></div><div class="card">Sales value<b>${RM(a.sales)}</b></div>
    <div class="card">Orders<b>${a.orders}</b></div><div class="card">Average order<b>${RM(a.aov)}</b></div>
    <div class="card">Gross profit estimate<b>${RM(a.gross)}</b></div><div class="card">Unpaid balance<b>${RM(a.outstanding)}</b></div>
    <div class="card">Discounts given<b>${RM(a.discounts)}</b></div><div class="card">Member repeat rate<b>${a.repeatRate}%</b></div>
    <div class="card">Points issued<b>${a.pointsIssued}</b></div><div class="card">Points redeemed<b>${a.pointsRedeemed}</b></div></div>
  <div class="ana-grid">
    <div class="card"><h3>Daily collections</h3>${sparkBars(days)}<p class="mut">Payments received (not orders booked), shown by order date.</p></div>
    <div class="card"><h3>Payment breakdown</h3><div class="mix-track" aria-label="Payment method share">${payment.map(x=>`<span style="width:${a.collected?x.total/a.collected*100:0}%;background:${x.name==='Cash'?'var(--pri)':'var(--pri2)'}"></span>`).join('')}</div>
      ${payment.map(x=>`<div class="ana-row"><span>${x.name}</span><b>${RM(x.total)} (${a.collected?Math.round(x.total/a.collected*100):0}%)</b></div>`).join('')}
      <p class="mut">Refund transactions are recorded separately in Reports → Cash in / out.</p></div>
    <div class="card"><h3>Top products by sales value</h3>${topProducts.length?topProducts.map(p=>`<div style="margin:8px 0"><div class="ana-row"><span>${esc(p.name)} · ${p.qty} units</span><b>${RM(p.total)}</b></div><div class="mix-track"><span style="width:${p.total/maxProd*100}%"></span></div></div>`).join(''):'<p class="mut">No product sales in this period.</p>'}</div>
    <div class="card"><h3>Top members</h3>${topCustomers.length?topCustomers.map((p,i)=>`<div class="ana-row"><span>${i+1}. ${esc(p.name)} · ${p.orders} orders</span><b>${RM(p.total)}</b></div>`).join(''):'<p class="mut">No member transactions in this period.</p>'}</div>
  </div>
  <div class="card"><h3>Transaction audit</h3>${tbl(['#','Date','Member / customer','Payment','Sale value','Collected','Discount','Status'],all.slice().reverse().map(o=>[o.no,esc(o.date),esc(o.customer),esc(o.payment),RM(o.total),RM(o.paid),RM(o.discount),tag(o.status)]))}
    <p class="mut">Gross profit uses recorded item cost snapshots, not rent, tax or all operating expenses. Legacy items without cost data may make this estimate too high. Loyalty points are issued only for eligible completed POS sales.</p></div>`;
}
function exportAnalytics() {
 const dates=recentDays(analyticsDays), start=dates[0], end=dates.at(-1);
 const os=db.orders.filter(o=>o.date>=start&&o.date<=end);
 const rows=[['Order','Date','Customer','Customer ID','Staff','Payment','Items','Subtotal','Discount','Points Redeemed','Total','Paid','Status'],
   ...os.map(o=>[o.no,o.date,o.customer,o.customerId??'',sellerName(o),o.payment,(o.items||[]).map(i=>i.name+' ×'+i.qty).join('; '),o.subtotal??o.total,o.discount??0,o.redeemedPoints??0,o.total,o.paid,o.status])];
 const csv=rows.map(row=>row.map(v=>'"'+String(v??'').replace(/"/g,'""')+'"').join(',')).join('\r\n');
 dl(`twotales-analytics-${start}-to-${end}.csv`,csv,'text/csv;charset=utf-8');
}

