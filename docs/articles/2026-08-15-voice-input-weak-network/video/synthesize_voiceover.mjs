import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';

const [textPath, outputPath] = process.argv.slice(2);
if (!textPath || !outputPath) throw new Error('Usage: node synthesize_voiceover.mjs narration.txt voiceover.wav');

const apiConfigPath = '/Users/liangkang/AIWorkProjects/doubao-asr-demo/gaip-voice-demo-package/bailian-config.json';
const voiceConfigPath = '/Users/liangkang/AIWorkProjects/wechatcontent/automationPost/config/akang_tts_voice.json';
const [apiConfig, voiceConfig, rawText] = await Promise.all([
  readFile(apiConfigPath, 'utf8').then(JSON.parse),
  readFile(voiceConfigPath, 'utf8').then(JSON.parse),
  readFile(resolve(textPath), 'utf8'),
]);
const text = rawText.split(/\r?\n/).map((line) => line.trim()).filter(Boolean).join('');
const endpoint = `${apiConfig.base_url.replace(/\/$/, '')}/api/v1/services/audio/tts/SpeechSynthesizer`;
const response = await fetch(endpoint, {
  method: 'POST',
  headers: {Authorization: `Bearer ${apiConfig.api_key}`, 'Content-Type': 'application/json'},
  body: JSON.stringify({model: voiceConfig.model, input: {text, voice: voiceConfig.voice, format: voiceConfig.synthesis_output.format, sample_rate: voiceConfig.synthesis_output.sample_rate_hz}}),
});
const result = await response.json();
if (!response.ok || result.code || !result.output?.audio?.url) throw new Error(`CosyVoice synthesis failed: ${JSON.stringify(result)}`);
const audio = await fetch(result.output.audio.url);
if (!audio.ok) throw new Error(`Audio download failed: HTTP ${audio.status}`);
const output = resolve(outputPath);
await mkdir(dirname(output), {recursive: true});
await writeFile(output, Buffer.from(await audio.arrayBuffer()));
console.log(JSON.stringify({characters: result.usage?.characters ?? text.length, model: voiceConfig.model, voice: voiceConfig.voice, output}));
