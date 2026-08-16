import {Composition} from 'remotion';
import {VoiceInputWeakNetwork} from './video';

export const Root = () => (
  <Composition
    id="VoiceInputWeakNetwork"
    component={VoiceInputWeakNetwork}
    durationInFrames={1260}
    fps={30}
    width={1080}
    height={1440}
  />
);
