import React from 'react';
import {Audio} from '@remotion/media';
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
} from 'remotion';

const C = {
  bg: '#0e1712', panel: '#17231c', line: '#375044', text: '#f6f2e8',
  muted: '#a9b8ae', green: '#55d69d', yellow: '#f2ca58', blue: '#3085f5', red: '#fa765e',
};
const font = 'PingFang SC, Microsoft YaHei, Noto Sans CJK SC, Arial, sans-serif';
const clamp = {extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const};
const ease = Easing.bezier(0.16, 1, 0.3, 1);

const captions = [
  {s: 0, e: 125, t: 'AI语音输入最烦的，不是慢。'},
  {s: 125, e: 270, t: '是声波还在跳，文字却迟迟不来。'},
  {s: 270, e: 375, t: '你不知道它有没有听到，也不知道是网络卡住，还是识别失败。'},
  {s: 375, e: 480, t: '我一开始想过：要不要重做一套离线兜底？'},
  {s: 480, e: 610, t: '但为了小概率场景，加完整录音、上传和重试，成本太高。'},
  {s: 610, e: 720, t: '后来我只做了两件事：网络差时解释等待；断网时明确停止。'},
  {s: 720, e: 930, t: '再用 Mac 自带工具，把低带宽、丢包和延迟复现出来。'},
  {s: 930, e: 1260, t: '很多体验问题，不在规划里，而在真的用起来以后。'},
];

const Header = () => {
  const f = useCurrentFrame();
  return <>
    <div style={{position:'absolute', left:64, right:64, top:56, display:'flex', justifyContent:'space-between', fontFamily:font, fontSize:26, fontWeight:800, color:C.muted}}>
      <span style={{color:C.green}}>AI 工作流实战 #11</span><span>真实使用 · 真实补课</span>
    </div>
    <div style={{position:'absolute', left:64, right:64, top:112, height:5, background:C.line}}>
      <div style={{height:'100%', width:`${interpolate(f,[0,1260],[0,100],clamp)}%`, background:C.green}} />
    </div>
  </>;
};

const Waveform = () => {
  const f = useCurrentFrame();
  const heights = [44,82,125,70,145,98,55,130,75,151,95,48,120,66,140,90,55,115,75,145];
  return <div style={{display:'flex', alignItems:'center', justifyContent:'center', gap:12, height:155}}>
    {heights.map((h,i) => <div key={i} style={{width:13, height:h + Math.sin((f+i*7)/5)*13, borderRadius:12, background:C.blue}} />)}
  </div>;
};

const InputPanel = ({warning = false, offline = false}: {warning?: boolean; offline?: boolean}) => {
  const f = useCurrentFrame();
  const seconds = Math.min(7, Math.floor(f / 30));
  return <div style={{width:900, background:'#f7f7f4', border:'3px solid #e2e2dd', padding:'30px 34px 34px', color:'#222', boxShadow:'0 18px 0 rgba(0,0,0,.18)'}}>
    <div style={{display:'flex', justifyContent:'space-between', fontFamily:font, fontSize:25, fontWeight:800}}><span><b style={{color:C.green}}>●</b> 自在说 · 正在聆听</span><span style={{fontVariantNumeric:'tabular-nums'}}>{offline ? '—' : `00:0${seconds}`}</span></div>
    {offline ? <div style={{height:180, display:'flex', alignItems:'center', fontSize:86, color:'#ef8b29'}}>⌁ <span style={{fontSize:31, marginLeft:30, color:'#3b3b3b'}}>检测到断网，请连接网络后再使用。</span></div> : <Waveform />}
    {!offline && <div style={{borderTop:'2px solid #deded9', paddingTop:23, color:'#b1b1aa', fontFamily:font, fontSize:30, fontWeight:800}}>◌　正在捕捉你的语音…</div>}
    {warning && <div style={{marginTop:24, padding:'21px 22px', borderLeft:`9px solid ${C.green}`, background:'#eaf6ee', color:'#147555', fontSize:25, lineHeight:1.4, fontWeight:850, fontFamily:font}}>当前网络环境差，可能会花更多时间，请耐心等待。</div>}
  </div>;
};

const Hook = () => {
  const f = useCurrentFrame();
  const timer = Math.min(7, Math.floor(interpolate(f,[0,135],[0,7],clamp)));
  const appear = interpolate(f,[0,16],[0,1],{easing:ease,...clamp});
  return <div style={{position:'absolute', top:190, left:64, right:64, fontFamily:font, opacity:appear}}>
    <div style={{color:C.text, fontSize:68, lineHeight:1.16, fontWeight:950}}>声波还在跳</div>
    <div style={{color:C.yellow, fontSize:68, lineHeight:1.16, fontWeight:950, marginTop:10}}>文字却没出来</div>
    <div style={{position:'absolute', right:5, top:165, color:C.muted, fontSize:42, fontWeight:900, fontVariantNumeric:'tabular-nums'}}>00:0{timer}</div>
    <div style={{marginTop:80}}><InputPanel /></div>
  </div>;
};

const Unknown = () => {
  const f = useCurrentFrame() - 270;
  const cards = [['麦克风听到了吗？','声波在动'],['网络发出去了吗？','文字没回来']];
  return <div style={{position:'absolute', left:64, right:64, top:210, fontFamily:font}}>
    <div style={{fontSize:59, lineHeight:1.2, fontWeight:900, color:C.text}}>用户不知道<br/><span style={{color:C.yellow}}>系统到底卡在哪</span></div>
    <div style={{display:'flex', gap:22, marginTop:70}}>{cards.map(([a,b],i) => {
      const o = interpolate(f,[i*35+10,i*35+32],[0,1],{easing:ease,...clamp});
      return <div key={a} style={{width:450, height:300, padding:32, opacity:o, transform:`translateY(${(1-o)*44}px)`, background:C.panel, border:`2px solid ${i===1?C.yellow:C.line}`}}>
        <div style={{color:C.muted, fontSize:26, fontWeight:800}}>等待的时候，脑子里只有一句</div>
        <div style={{marginTop:48, color:C.text, fontSize:38, fontWeight:900, lineHeight:1.35}}>{a}</div>
        <div style={{position:'absolute', bottom:28, color:i===1?C.yellow:C.green, fontSize:28, fontWeight:900}}>{b}</div>
      </div>;
    })}</div>
  </div>;
};

const Fix = () => {
  const f = useCurrentFrame() - 480;
  const stage = f < 130;
  const title = stage ? '不为小概率弱网\n重做一套大系统' : '先把“不知道”\n变成明确的解释';
  const scale = interpolate(f,[0,20],[.96,1],{easing:ease,...clamp});
  return <div style={{position:'absolute', left:64, right:64, top:190, fontFamily:font, transform:`scale(${scale})`}}>
    <div style={{whiteSpace:'pre-line', color:C.text, fontSize:60, lineHeight:1.22, fontWeight:950}}>{title}</div>
    {stage ? <div style={{marginTop:68, display:'flex', gap:18}}>{['完整录音','文件上传','失败重试','结果去重'].map((x,i)=><div key={x} style={{padding:'20px 24px', border:'2px solid #74483e', color:'#ff9d82', fontSize:27, fontWeight:850}}>{x}</div>)}</div> : <div style={{marginTop:65, display:'grid', gap:25}}>
      <div style={{padding:32, background:'#eaf6ee', borderLeft:`12px solid ${C.green}`, color:'#147555', fontSize:31, fontWeight:900}}>弱网：告诉用户还在等待</div>
      <div style={{padding:32, background:'#fff0ea', borderLeft:`12px solid ${C.red}`, color:'#c94c37', fontSize:31, fontWeight:900}}>断网：告诉用户连接网络后再试</div>
    </div>}
  </div>;
};

const Test = () => {
  const f = useCurrentFrame() - 720;
  const values = [['带宽','1 Mbps'],['丢包','10%'],['延迟','500 ms']];
  return <div style={{position:'absolute', left:64, right:64, top:175, fontFamily:font}}>
    <div style={{fontSize:55, lineHeight:1.22, color:C.text, fontWeight:950}}>别靠感觉测弱网<br/><span style={{color:C.green}}>Mac 有自带的测试工具</span></div>
    <div style={{marginTop:38, height:405, overflow:'hidden', border:`2px solid ${C.line}`}}><Img src={staticFile('conditioner.png')} style={{width:'100%', height:'100%', objectFit:'cover', objectPosition:'center'}} /></div>
    <div style={{display:'flex', gap:18, marginTop:32}}>{values.map(([a,b],i)=>{const o=interpolate(f,[90+i*26,110+i*26],[0,1],{easing:ease,...clamp}); return <div key={a} style={{flex:1, opacity:o, background:C.panel, borderTop:`5px solid ${C.green}`, padding:'20px 18px'}}><div style={{fontSize:24,color:C.muted,fontWeight:800}}>{a}</div><div style={{fontSize:37,color:C.text,fontWeight:900,marginTop:8}}>{b}</div></div>})}</div>
  </div>;
};

const Ending = () => {
  const f = useCurrentFrame() - 930;
  const o = interpolate(f,[0,22],[0,1],{easing:ease,...clamp});
  return <div style={{position:'absolute', left:64, right:64, top:228, fontFamily:font, opacity:o}}>
    <div style={{fontSize:56, color:C.muted, fontWeight:850}}>好的体验，不只来自规划</div>
    <div style={{marginTop:24, fontSize:76, lineHeight:1.18, color:C.text, fontWeight:950}}>更来自<br/><span style={{color:C.yellow}}>真的用起来以后</span></div>
    <div style={{marginTop:95, padding:'28px 32px', borderLeft:`12px solid ${C.green}`, background:C.panel, color:C.text, fontSize:31, lineHeight:1.5, fontWeight:850}}>声波仍在跳动时，至少让用户知道：<br/>系统没停，只是在等网络回来。</div>
  </div>;
};

const Caption = () => {
  const f = useCurrentFrame();
  const c = captions.find(x => f >= x.s && f < x.e)?.t ?? '';
  return <><div style={{position:'absolute', left:64, right:64, bottom:76, minHeight:126, padding:'22px 28px', background:'rgba(14,23,18,.96)', borderTop:`3px solid ${C.yellow}`, color:C.text, fontFamily:font, fontSize:37, fontWeight:850, textAlign:'center', lineHeight:1.4}}>{c}</div>
    <div style={{position:'absolute', left:64, right:64, bottom:30, display:'flex', justifyContent:'space-between', fontFamily:font, fontSize:21, color:C.muted, fontWeight:750}}><span>作者：阿康 · 公众号@阿康AI探索号</span><span>AI语音输入卡住时</span></div></>;
};

export const VoiceInputWeakNetwork: React.FC = () => {
  const f = useCurrentFrame();
  const scene = f < 270 ? <Hook /> : f < 480 ? <Unknown /> : f < 720 ? <Fix /> : f < 930 ? <Test /> : <Ending />;
  return <AbsoluteFill style={{backgroundColor:C.bg, backgroundImage:'linear-gradient(rgba(255,255,255,.028) 1px, transparent 1px),linear-gradient(90deg,rgba(255,255,255,.028) 1px,transparent 1px)', backgroundSize:'38px 38px'}}>
    <Audio src={staticFile('voiceover.wav')} volume={1} />
    <Header />{scene}<Caption />
  </AbsoluteFill>;
};
