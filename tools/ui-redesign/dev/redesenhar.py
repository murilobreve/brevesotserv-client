from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, hashlib, shutil, zipfile

import argparse
parser=argparse.ArgumentParser()
parser.add_argument('--reference',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
REF=args.reference
OUT=args.output
for sub in ['1-tema','2-icones-painel','3-janelas-extras','previews','dev']:(OUT/sub).mkdir(parents=True,exist_ok=True)
P={'outer':'#08090f','edge':'#5e5261','edge_hi':'#8f7e6b','gold':'#b69a60','gold_hi':'#ebd7a1','gold_dark':'#6b5537','body':'#191821','title':'#101018','panel':'#21202b','well':'#101018','ink':'#0d0d15','hover':'#302b3d','selected':'#2c2540','violet':'#b296f5','violet_dim':'#725696','pearl':'#e6ddc7','text':'#ebe7ef','muted':'#b4afc3','green':'#a8d486','red':'#ed877a'}
def rgba(c):
    if isinstance(c,tuple):return c
    return tuple(int(c[i:i+2],16) for i in (1,3,5))+(255,)
def new(w,h):return Image.new('RGBA',(w,h),(0,0,0,0))
def rect(d,b,c):d.rectangle(b,fill=rgba(P.get(c,c)))
def line(d,pts,c):d.line(pts,fill=rgba(P.get(c,c)),width=1)
def poly(d,pts,c):d.polygon(pts,fill=rgba(P.get(c,c)))
def beveled(w,h,fill='panel',border='edge',highlight='edge_hi',b=4):
    im=new(w,h);d=ImageDraw.Draw(im)
    poly(d,[(2,0),(w-3,0),(w-1,2),(w-1,h-3),(w-3,h-1),(2,h-1),(0,h-3),(0,2)],'outer')
    poly(d,[(2,1),(w-3,1),(w-2,2),(w-2,h-3),(w-3,h-2),(2,h-2),(1,h-3),(1,2)],border)
    rect(d,(2,2,w-3,h-3),fill)
    if b==2:
        line(d,[(2,1),(w-3,1)],highlight);line(d,[(1,2),(1,h-3)],highlight)
        line(d,[(2,h-2),(w-3,h-2)],'outer');line(d,[(w-2,2),(w-2,h-3)],'outer')
        return im
    line(d,[(3,2),(w-4,2)],highlight);line(d,[(2,3),(2,h-4)],highlight)
    line(d,[(3,h-3),(w-3,h-3),(w-3,3)],'outer')
    # All corner facets stay within the fixed border.
    if b>=4:
        for x,y in [(3,3),(w-4,3),(3,h-4),(w-4,h-4)]:d.point((x,y),fill=rgba(P['gold_dark']))
    return im
def save(im,folder,name):im.save(OUT/folder/(name+'.png'))

# Stable native-resolution base pieces. Central nine-slice areas are uniform.
for name,fill,border,b in [('panel','panel','edge',4),('panel_on','selected','violet',4),('well','well','edge',3),('notice','panel','gold',4),('popup','panel','edge',2)]:
    save(beveled(32,32,fill,border,'violet' if name=='panel_on' else 'edge_hi',b),'1-tema',name)
for focus in [False,True]:
    im=beveled(32,22,'ink','violet' if focus else 'edge','violet' if focus else 'gold_dark',3)
    save(im,'1-tema','input_focus' if focus else 'input')
for state in ['','_hover','_pressed','_disabled']:
    fill={'':'#282631','_hover':'#373044','_pressed':'#18151f','_disabled':'#222129'}[state]
    border={'':'edge','_hover':'violet','_pressed':'violet_dim','_disabled':'#46414e'}[state]
    hi={'':'edge_hi','_hover':'#c5aae9','_pressed':'#4b3a65','_disabled':'#554e5e'}[state]
    save(beveled(64,22,fill,border,hi),'1-tema','button'+state)
    fill={'':'#dfd5be','_hover':'#f3e9d0','_pressed':'#c1b296','_disabled':'#514c5b'}[state]
    border={'':'gold','_hover':'gold_hi','_pressed':'gold_dark','_disabled':'#655d70'}[state]
    hi={'':'#faf3e2','_hover':'#fffaf0','_pressed':'#9f8d6e','_disabled':'#71697d'}[state]
    save(beveled(64,22,fill,border,hi),'1-tema','button_pearl'+state)
for name,fill,border in [('tab','title','edge'),('tab_hover','hover','edge_hi'),('tab_on','selected','violet')]:
    im=beveled(64,24,fill,border,border,2);d=ImageDraw.Draw(im)
    rect(d,(2,22,61,23),'violet' if name=='tab_on' else 'edge')
    save(im,'1-tema',name)
for name,w,h,b,top in [('window',256,256,6,30),('section',64,64,4,21)]:
    im=beveled(w,h,'body','edge','edge_hi',b);d=ImageDraw.Draw(im)
    rect(d,(b,b,w-b-1,top-3),'title')
    line(d,[(b,top-2),(w-b-1,top-2)],'gold_dark')
    line(d,[(b,top-1),(w-b-1,top-1)],'outer')
    # Tiny corner glints, inside 6/4 px fixed side strips.
    line(d,[(3,4),(3,12 if top==30 else 9)],'gold')
    line(d,[(w-4,4),(w-4,12 if top==30 else 9)],'violet_dim')
    if name=='window':
        line(d,[(4,4),(4,7)],'gold_hi');line(d,[(w-5,4),(w-5,7)],'gold')
    save(im,'1-tema',name)

def triangle(d,cx,cy,dir,color,small=False):
    s=2 if small else 3
    if dir=='down':pts=[(cx-s,cy-1),(cx+s,cy-1),(cx,cy+s-1)]
    elif dir=='up':pts=[(cx-s,cy+1),(cx+s,cy+1),(cx,cy-s+1)]
    elif dir=='right':pts=[(cx-1,cy-s),(cx-1,cy+s),(cx+s-1,cy)]
    else:pts=[(cx+1,cy-s),(cx+1,cy+s),(cx-s+1,cy)]
    poly(d,pts,color)
combo=new(91,60)
for i in range(3):
    frame=beveled(91,20,'hover' if i==1 else 'ink','violet' if i==2 else 'edge','edge_hi',3);d=ImageDraw.Draw(frame)
    rect(d,(72,3,87,16),'selected' if i==2 else 'panel');line(d,[(71,3),(71,16)],'edge')
    triangle(d,80,9,'up' if i==2 else 'down','violet' if i==2 else 'gold_hi')
    combo.alpha_composite(frame,(0,i*20))
save(combo,'1-tema','combobox')
for horiz in [False,True]:
    track=beveled(10,32,'ink','edge','outer',2)
    if horiz:track=track.transpose(Image.Transpose.ROTATE_90)
    save(track,'1-tema','scroll_track_h' if horiz else 'scroll_track')
    for hover in [False,True]:
        thumb=beveled(10,24,'#675376' if hover else '#4a4255','violet' if hover else 'edge_hi','gold_hi' if hover else 'gold',4)
        if horiz:thumb=thumb.transpose(Image.Transpose.ROTATE_90)
        save(thumb,'1-tema','scroll_thumb'+('_h' if horiz else '')+('_hover' if hover else ''))
    sheet=new(20,20)
    for row in range(2):
        for col in range(2):
            frame=beveled(10,10,'hover' if col else 'title','violet' if col else 'edge','edge_hi',2)
            d=ImageDraw.Draw(frame);triangle(d,4,4,('left' if row==0 else 'right') if horiz else ('up' if row==0 else 'down'),'gold_hi' if col else 'muted',True)
            sheet.alpha_composite(frame,(col*10,row*10))
    save(sheet,'1-tema','scroll_arrows_h' if horiz else 'scroll_arrows')
for open in [False,True]:
    im=new(8,8);triangle(ImageDraw.Draw(im),3,3,'down' if open else 'right','gold_hi',True)
    save(im,'1-tema','fold_open' if open else 'fold_closed')

def gemstone(size,base,light,shadow):
    im=new(size,size);d=ImageDraw.Draw(im);c=(size-1)//2
    poly(d,[(c,0),(size-2,c-1),(size-1,c),(c+1,size-1),(c,size-1),(0,c)],'outer')
    poly(d,[(c,1),(size-2,c),(c,size-2),(1,c)],base)
    poly(d,[(c,1),(c-2,c),(1,c)],light)
    poly(d,[(c,1),(size-2,c),(c+1,c+1)],base)
    poly(d,[(c+1,c),(size-2,c),(c,size-2)],shadow)
    line(d,[(c,2),(c-2,c),(c,size-3)],light)
    d.point((c-1,2),fill=rgba('#fff4da'));return im
for name,colors in [('amethyst',('#9270d4','#d7bfff','#483160')),('gold',('#c39440','#ffe3a0','#805423')),('pearl',('#d8d6e3','#fff6e1','#8c879e')),('sapphire',('#3d91c7','#b1eaff','#254e88'))]:
    save(gemstone(12,*colors),'1-tema','gem_'+name)

def icon(name):
    im=new(16,16);d=ImageDraw.Draw(im)
    O='#090a10';G='#c99c53';L='#ffe0a0';S='#705035';V='#a181dc';VL='#e5ceff';VS='#53386e'
    def R(b,c):rect(d,b,c)
    def T(p,c):poly(d,p,c)
    def N(p,c):line(d,p,c)
    if name=='board':
        R((4,1,11,2),O);R((5,2,10,7),G);R((5,2,6,5),L);R((7,7,8,10),G)
        N([(4,2),(2,2),(2,6),(4,8)],S);N([(11,2),(13,2),(13,6),(10,8)],G)
        N([(3,3),(3,5),(4,6)],L);R((6,10,9,12),S);R((3,13,12,14),O);R((4,12,11,13),G);R((4,12,8,12),L)
    elif name=='rates':
        T([(8,0),(9,4),(12,3),(12,6),(14,9),(13,13),(10,15),(4,15),(1,11),(2,7),(5,4),(5,8)],O)
        T([(8,1),(8,5),(11,4),(10,7),(13,9),(12,12),(9,14),(4,14),(2,10),(4,6),(5,10)],'#cb6138')
        T([(7,5),(8,9),(10,7),(11,11),(9,13),(5,13),(4,10)],'#f2b958');T([(7,9),(9,12),(6,12)],'#fff0b8')
    elif name=='tasks':
        T([(7,0),(14,7),(7,15),(0,7)],O);T([(7,2),(12,7),(7,12),(2,7)],G);T([(7,4),(10,7),(7,10),(4,7)],'#5d3734')
        N([(7,0),(7,4)],L);N([(0,7),(4,7)],L);N([(11,7),(15,7)],G);N([(7,11),(7,15)],G)
        N([(4,7),(6,9),(11,4)],'#f4deae')
    elif name=='trail':
        N([(3,14),(5,12),(5,10),(8,9),(8,6),(11,5)],O);N([(3,13),(5,11),(5,9),(8,8),(8,5),(11,4)],G)
        R((10,1,10,7),L);T([(11,1),(15,2),(11,4)],'#c86c58');R((1,13,2,14),L);R((6,9,7,10),S)
    elif name in ['taskshop','loot']:
        base=G if name=='taskshop' else '#55a56b';light=L if name=='taskshop' else '#b9eb9b';shade=S if name=='taskshop' else '#315c48'
        T([(5,1),(10,1),(9,5),(13,8),(14,12),(12,15),(3,15),(1,12),(2,8),(6,5)],O)
        T([(5,2),(10,2),(9,5),(12,8),(13,11),(11,14),(4,14),(2,11),(3,8),(6,5)],base)
        N([(5,6),(9,6)],shade);N([(4,8),(3,10),(4,12)],light);T([(8,8),(10,10),(8,12),(6,10)],light);R((9,12,11,13),shade)
    elif name=='rarity':
        T([(3,2),(11,2),(15,7),(8,15),(0,7)],O);T([(4,3),(10,3),(13,7),(8,13),(2,7)],V)
        T([(4,3),(7,3),(5,7),(2,7)],VL);T([(7,3),(10,3),(9,7),(5,7)],'#c7a8f5');T([(9,7),(13,7),(8,13)],VS);N([(2,7),(13,7)],'#ecdbff');N([(5,7),(8,13)],'#b89be5')
    elif name=='healbot':
        T([(7,0),(14,3),(13,10),(7,15),(1,10),(0,3)],O);T([(7,1),(13,4),(12,10),(7,13),(2,10),(1,4)],'#713a42');N([(2,4),(7,2),(11,4)],'#c07876')
        R((6,4,8,10),'#ec9a86');R((4,6,10,8),'#ec9a86');R((6,4,6,7),'#ffdebd')
    elif name=='wiki':
        T([(1,2),(6,2),(8,3),(10,2),(14,2),(14,13),(9,13),(8,15),(6,13),(1,13)],O)
        T([(2,3),(6,3),(7,4),(7,12),(3,11),(2,12)],'#dfcba0');T([(8,4),(10,3),(13,3),(13,12),(9,11),(8,12)],'#bea579')
        N([(3,5),(5,5)],S);N([(3,7),(5,7)],S);N([(3,9),(5,9)],S);N([(10,5),(12,5)],S);N([(10,7),(12,7)],S);N([(10,9),(12,9)],S);N([(7,4),(7,12)],L)
    elif name=='messages':
        T([(2,2),(13,2),(15,4),(15,10),(13,12),(6,12),(2,15),(2,12),(0,10),(0,4)],O)
        T([(2,3),(12,3),(14,5),(14,9),(12,11),(5,11),(3,13),(3,11),(1,9),(1,5)],'#a99eb4');N([(3,4),(11,4)],'#e9dec7');N([(4,6),(11,6)],'#5b4d6a');N([(4,8),(9,8)],'#5b4d6a')
    elif name=='bonus':
        T([(7,1),(14,7),(7,14),(0,7)],O);T([(7,2),(12,7),(7,12),(2,7)],'#75607c');T([(7,3),(7,7),(3,7)],'#cfc1a2');T([(7,7),(12,7),(7,12)],VS)
        R((6,4,8,10),VL);R((4,6,10,8),VL);d.point((3,2),fill=rgba(L));d.point((13,12),fill=rgba(V))
    return im
for name in ['board','rates','tasks','trail','taskshop','bonus','rarity','loot','healbot','wiki','messages']:save(icon(name),'2-icones-painel',name)

def mythos_mark():
    im=new(16,16);d=ImageDraw.Draw(im)
    # Native 16 px sword-and-wings emblem; pixels read as a mark, not lettering.
    poly(d,[(7,0),(9,2),(8,9),(7,12),(6,9),(6,2)],'#dcd3ed');line(d,[(7,2),(7,9)],'#fff4d4')
    poly(d,[(0,3),(3,5),(5,5),(5,7),(2,6),(0,5)],'#b29bce');poly(d,[(15,3),(12,5),(9,5),(9,7),(12,6),(15,5)],'#9476b6')
    line(d,[(1,7),(4,8),(5,8)],'#d4c1e8');line(d,[(10,8),(12,8),(14,7)],'#b39bcf')
    rect(d,(5,10,9,10),'gold');rect(d,(7,11,7,14),'gold_hi');return im
for name,kind in [('button',None),('botao-barra-huntboard','board'),('botao-barra-hunttasks','tasks'),('botao-barra-raritymarket','rarity'),('botao-barra-healbot','healbot'),('botao-barra-wiki','wiki')]:
    sheet=new(40,20)
    for i in range(2):
        frame=beveled(20,20,'selected' if i else 'title','violet' if i else 'edge','gold' if i else 'edge_hi',3)
        frame.alpha_composite(mythos_mark() if kind is None else icon(kind),(2,2));sheet.alpha_composite(frame,(i*20,0))
    save(sheet,'2-icones-painel',name)

# Action glyphs drawn directly at 14x14. No scaling of the production assets.
for name in ['change','improve','reroll']:
    im=new(14,14);d=ImageDraw.Draw(im)
    if name=='change':
        line(d,[(2,4),(11,4)],'gold');poly(d,[(9,1),(12,4),(9,6)],'gold_hi');line(d,[(11,9),(2,9)],'violet');poly(d,[(4,6),(1,9),(4,12)],'#d8bfff')
    elif name=='improve':
        poly(d,[(6,1),(12,7),(9,7),(9,12),(4,12),(4,7),(1,7)],'outer');poly(d,[(6,2),(10,6),(8,6),(8,11),(5,11),(5,6),(2,6)],'#8ab77a');line(d,[(4,5),(6,3),(8,5)],'#d5efb2')
    else:
        line(d,[(2,5),(2,3),(4,1),(9,1),(11,3),(11,5)],'gold');poly(d,[(8,4),(12,7),(12,2)],'gold_hi')
        line(d,[(11,8),(11,10),(9,12),(4,12),(2,10),(2,8)],'violet');poly(d,[(5,9),(1,6),(1,11)],'#d8bfff')
    save(im,'3-janelas-extras',name)
for name in ['choose','remove']:
    sheet=new(20,40)
    for i in range(2):
        im=beveled(20,20,'hover' if i else 'panel','violet' if i else 'edge','gold' if i else 'edge_hi',3);d=ImageDraw.Draw(im)
        if name=='remove':
            c='#ffb7a0' if i else '#caa394';line(d,[(6,6),(13,13)],c);line(d,[(13,6),(6,13)],c);line(d,[(6,7),(12,13)],'#78585a')
        else:
            rect(d,(5,8,13,14),'gold_dark');rect(d,(5,8,13,9),'gold');line(d,[(7,7),(7,5),(11,5),(11,7)],'gold_hi');line(d,[(8,11),(10,13),(14,9)],'#e8d8b0')
        sheet.alpha_composite(im,(0,i*20))
    save(sheet,'3-janelas-extras',name)
im=new(7,9);d=ImageDraw.Draw(im);poly(d,[(2,0),(4,0),(4,2),(6,4),(6,7),(5,8),(1,8),(0,7),(0,4),(2,2)],'outer');rect(d,(2,1,4,2),'gold_hi');poly(d,[(2,3),(4,3),(5,5),(5,7),(1,7),(1,5)],'gold');line(d,[(1,5),(1,6)],'gold_hi');save(im,'3-janelas-extras','container')

# Contract and alpha validation against original files.
manifest=[]
borders={'window':{'top':30,'right':6,'bottom':6,'left':6},'section':{'top':21,'right':4,'bottom':4,'left':4},'input':3,'input_focus':3,'well':3,'popup':2,'tab':2,'tab_hover':2,'tab_on':2,'combobox':{'top':3,'right':20,'bottom':3,'left':3},'scroll_track':2,'scroll_track_h':2}
for folder in ['1-tema','2-icones-painel','3-janelas-extras']:
    for p in sorted((OUT/folder).glob('*.png')):
        original=Image.open(REF/folder/p.name).convert('RGBA');im=Image.open(p)
        assert im.size==original.size and im.mode=='RGBA',p
        assert set(im.getchannel('A').get_flattened_data())<={0,255},p
        layout='single';frame=list(im.size)
        if folder=='2-icones-painel' and im.size==(40,20):layout='horizontal: normal, on';frame=[20,20]
        if p.stem=='combobox':layout='vertical: normal, hover, on';frame=[91,20]
        if p.stem.startswith('scroll_arrows'):layout='2x2: upper/left normal, hover; lower/right normal, hover';frame=[10,10]
        if folder=='3-janelas-extras' and im.size==(20,40):layout='vertical: normal, hover';frame=[20,20]
        if folder=='1-tema' and p.stem not in borders and not p.stem.startswith(('gem_','fold_','scroll_arrows')):border=4
        else:border=borders.get(p.stem,0)
        manifest.append({'path':folder+'/'+p.name,'size':list(im.size),'fixed_border':border,'frame':frame,'layout':layout,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
for prefix in ['button','button_pearl']:
    masks=[Image.open(OUT/'1-tema'/(prefix+s+'.png')).getchannel('A').tobytes() for s in ['','_hover','_pressed','_disabled']]
    assert len(set(masks))==1,prefix
for name,fw,fh,cols,rows in [('combobox',91,20,1,3),('scroll_arrows',10,10,2,2),('scroll_arrows_h',10,10,2,2)]:
    im=Image.open(OUT/'1-tema'/(name+'.png'));masks=[im.crop((x*fw,y*fh,(x+1)*fw,(y+1)*fh)).getchannel('A').tobytes() for y in range(rows) for x in range(cols)];assert len(set(masks))==1,name

# Nine-slice simulator: only previews use resizing, never production pieces.
def sliced(im,size,border=4,top=None,right=None,bottom=None):
    w,h=im.size;W,H=size;l=border;t=top or border;r=right or border;b=bottom or border
    out=new(W,H);sx=[0,l,w-r,w];sy=[0,t,h-b,h];dx=[0,l,W-r,W];dy=[0,t,H-b,H]
    for y in range(3):
        for x in range(3):
            seg=im.crop((sx[x],sy[y],sx[x+1],sy[y+1]));dw=dx[x+1]-dx[x];dh=dy[y+1]-dy[y]
            out.alpha_composite(seg.resize((dw,dh),Image.Resampling.NEAREST),(dx[x],dy[y]))
    return out
F='/usr/share/fonts/truetype/dejavu/'
def font(size=11,bold=False,serif=False):return ImageFont.truetype(F+('DejaVuSerif' if serif else 'DejaVuSans')+('-Bold' if bold else '')+'.ttf',size)
def txt(im,xy,text,color='text',size=11,bold=False,serif=False):ImageDraw.Draw(im).text(xy,text,font=font(size,bold,serif),fill=rgba(P.get(color,color)))
def centered(im,xy,text,color='text',size=11,bold=False,serif=False):
    f=font(size,bold,serif);d=ImageDraw.Draw(im);bb=d.textbbox((0,0),text,font=f);d.text((xy[0]-(bb[2]-bb[0])//2,xy[1]),text,font=f,fill=rgba(P.get(color,color)))
def asset(im,name,box,b=4,top=None,right=None):
    x,y,w,h=box;src=Image.open(OUT/'1-tema'/(name+'.png'));im.alpha_composite(sliced(src,(w,h),b,top,right),(x,y))
def btn(im,xy,w,text,primary=False,disabled=False):
    x,y=xy;name='button_pearl' if primary else 'button';name+='_disabled' if disabled else '';asset(im,name,(x,y,w,22));centered(im,(x+w//2,y+4),text,'#7d778a' if disabled else ('#170f24' if primary else 'text'),10,True)
def sect(im,box,title):
    x,y,w,h=box;asset(im,'section',box,4,21);centered(im,(x+w//2,y+5),title,'pearl',11,True)
def window(screen,title,box):
    im=Image.open(REF/'4-prints'/screen).convert('RGBA');x,y,w,h=box;asset(im,'window',box,6,30)
    centered(im,(x+w//2,y+8),title,'pearl',14,True,True)
    return im
def small_icon(im,name,xy):im.alpha_composite(icon(name),xy)
def bar(im,box,value,color='violet'):
    x,y,w,h=box;d=ImageDraw.Draw(im);rect(d,(x,y,x+w-1,y+h-1),'edge');rect(d,(x+1,y+1,x+w-2,y+h-2),'ink');rect(d,(x+2,y+2,x+2+int((w-5)*value),y+h-3),color)
def sprite(im,screen,srcbox,xy):
    # Authentic supplied creature/item pixels in illustrative previews only.
    im.alpha_composite(Image.open(REF/'4-prints'/screen).convert('RGBA').crop(srcbox),xy)

# Proposed Hunt Board layout: data grouping and safe vs high multiplier distinction.
im=window('huntboard.png','HUNT RATES',(90,35,820,630))
txt(im,(106,75),'Escolha sua próxima caça',size=13,bold=True);txt(im,(106,96),'Confira XP, loot e dificuldade antes de sair da cidade.','muted')
txt(im,(680,78),'Novas rates em 00:19:25','gold_hi',11,True)
for i,(name,xp,loot) in enumerate([('Nightfiend','x9.8','x3.9'),('Flying Book','x9.8','x3.9'),('Energy Dragon','x9.7','x3.9'),('Spider','x9.6','x3.9')]):
    x=106+i*196;asset(im,'panel',(x,121,189,88));small_icon(im,'rates',(x+10,131));txt(im,(x+33,131),name,size=11,bold=True);txt(im,(x+12,155),'XP '+xp,'violet',12,True);txt(im,(x+100,155),'Loot '+loot,'gold_hi',12,True);txt(im,(x+12,180),'Mais bônus • mais desafio','muted',10)
asset(im,'input',(106,222,257,22),3);txt(im,(113,226),'Buscar monstro...','muted',10)
combo=Image.open(OUT/'1-tema/combobox.png').crop((0,0,91,20));im.alpha_composite(sliced(combo,(165,22),3,right=20),(372,222));txt(im,(379,226),'Todos os monstros',size=10)
im.alpha_composite(sliced(combo,(168,22),3,right=20),(547,222));txt(im,(554,226),'Maior XP',size=10);txt(im,(738,226),'□ Incluir bosses','muted',10)
asset(im,'well',(106,258,788,330),3);d=ImageDraw.Draw(im);rect(d,(110,262,889,286),'panel')
txt(im,(121,268),'MONSTRO','muted',10,True);txt(im,(506,268),'XP / LOOT','muted',10,True);txt(im,(690,268),'DIFICULDADE','muted',10,True);txt(im,(817,268),'XP AGORA','muted',10,True)
rows=[('Nightfiend','2.100 XP base · 56 spawns','x9.8','x3.9','Elevada','20.580'),('Flying Book','200 XP base · 63 spawns','x9.8','x3.9','Elevada','1.960'),('Energy Dragon','2.700 XP base · 67 spawns','x9.7','x3.9','Elevada','26.190'),('Spider','12 XP base · 141 spawns','x9.6','x3.9','Baixa','115'),('Necrovigil','8.000 XP base · 43 spawns','x9.5','x3.8','Elevada','76.000')]
for i,(name,desc,xp,loot,diff,total) in enumerate(rows):
    y=291+i*57
    rect(d,(110,y,883,y+54),'selected' if i==0 else ('#24212d' if i%2 else 'well'))
    if i==0:rect(d,(110,y,111,y+54),'violet')
    txt(im,(123,y+9),str(i+1),'muted',10);txt(im,(153,y+7),name,size=12,bold=True);txt(im,(153,y+28),desc,'muted',10)
    txt(im,(504,y+8),'XP '+xp,'violet',11,True);txt(im,(504,y+29),'Loot '+loot,'gold_hi',11,True);txt(im,(690,y+18),diff,'red' if diff=='Elevada' else 'green',10,True);txt(im,(817,y+18),total,size=11,bold=True)
asset(im,'scroll_track',(884,289,10,290),2);asset(im,'scroll_thumb',(884,292,10,48),4)
txt(im,(106,602),'XP base × rate atual; stage e bônus pessoais são aplicados depois.','muted',10)
btn(im,(106,628),83,'Anterior',disabled=True);centered(im,(475,633),'Página 1 de 17','muted',10);btn(im,(707,628),86,'Próxima');btn(im,(813,628),81,'Fechar')
im.save(OUT/'previews/01-hunt-board-proposta.png')

# Rarity Market: actual item sprites remain untouched, larger details and clear CTA.
im=window('market.png','RARITY MARKET',(86,24,830,621));d=ImageDraw.Draw(im)
for x,w,label,on in [(102,120,'Navegar',True),(229,120,'Vender',False),(356,150,'Minhas ofertas',False)]:
    asset(im,'tab_on' if on else 'tab',(x,64,w,24),2);centered(im,(x+w//2,70),label,'text' if on else 'muted',11,True)
txt(im,(722,70),'Banco: 829.800 gp','gold_hi',11,True)
asset(im,'input',(102,104,498,22),3);txt(im,(109,108),'Buscar item pelo nome...','muted',10)
combo=Image.open(OUT/'1-tema/combobox.png').crop((0,0,91,20))
for x,label in [(102,'Todos os tipos'),(271,'Todas as raridades'),(440,'Mais novos')]:im.alpha_composite(sliced(combo,(160,20),3,right=20),(x,135));txt(im,(x+7,138),label,size=10)
sect(im,(610,104,290,486),'Detalhes do item');asset(im,'well',(102,165,498,425),3)
items=[('Giant Sword','+6 Attack · +8% Crit Damage','95.000','Praeclarus'),('Two Handed Sword','+1% Sword','8.000','Communis'),('Demonrage Sword','+19 Attack · +9% Crit Chance','980.000','Mythicus'),('Fire Sword','+19 Attack · +22% Crit Damage','640.000','Mythicus'),('Magic Sword','+9% Sword · +18% Fire Resist','180.000','Legendarius'),('Dragon Lance','+13 Attack · +33% Ice Resist','210.000','Legendarius')]
colors=['#b296f5','#8bce98','#e6e0ee','#e6e0ee','#e4b45f','#e4b45f']
for i,(name,stats,price,grade) in enumerate(items):
    y=174+i*66;rect(d,(106,y,591,y+62),'selected' if i==0 else ('#24212d' if i%2 else 'well'))
    if i==0:rect(d,(106,y,107,y+62),'violet')
    # Draw original supplied frames; preserve rarity hues exactly.
    frames=Image.open(REF/'3-janelas-extras/frames.png').convert('RGBA');gradeidx=[3,1,5,5,4,4][i];im.alpha_composite(frames.crop((gradeidx*34,0,gradeidx*34+34,34)),(115,y+12))
    srcys=[195,237,280,322,365,491];sprite(im,'market.png',(111,srcys[i],140,srcys[i]+29),(117,y+14))
    txt(im,(160,y+8),name,colors[i],11,True);txt(im,(160,y+28),stats,'muted',10);txt(im,(160,y+45),grade,colors[i],9)
    txt(im,(510,y+21),price,'gold_hi',11,True);txt(im,(544,y+39),'gp','muted',10)
txt(im,(630,151),'Giant Sword','#cdb1ff',14,True);txt(im,(630,178),'Praeclarus · Espada de duas mãos','muted',10)
for y,label,value in [(218,'Ataque adicional','+6'),(253,'Dano crítico','+8%'),(288,'Life leech','+4%')]:txt(im,(630,y),label,'muted',11);txt(im,(847,y),value,'text',11,True)
line(d,[(626,326),(881,326)],'edge');txt(im,(630,343),'Preço','muted',11);txt(im,(630,367),'95.000 gp','gold_hi',22,True)
txt(im,(630,405),'Vendedor: GOD','muted',11);txt(im,(630,433),'Após a compra, confira a entrega','muted',10);txt(im,(630,449),'no local definido pelo servidor.','muted',10)
btn(im,(630,498),250,'Comprar item',True);txt(im,(630,537),'Confirmar preço antes da compra.','muted',10)
btn(im,(102,607),84,'Anterior',disabled=True);centered(im,(356,612),'Página 1 de 2 · 17 ofertas','muted',10);btn(im,(516,607),84,'Próxima');btn(im,(817,607),83,'Fechar')
im.save(OUT/'previews/02-rarity-market-proposta.png')

# Heal Bot: readable status, explicit labels, stable consistent controls.
im=window('healbot.png','HEAL BOT',(180,161,640,379));d=ImageDraw.Draw(im)
asset(im,'well',(196,201,128,290),3)
for i,(name,label) in enumerate([('healbot','Cura'),('loot','Poções'),('messages','Amigos'),('bonus','Suporte')]):
    y=207+i*34
    if i==0:asset(im,'panel_on',(200,y,120,29));
    small_icon(im,name,(208,y+6));txt(im,(234,y+6),label,'text' if i==0 else 'muted',11,True)
txt(im,(339,202),'Prioridade: de cima para baixo','pearl',11,True);txt(im,(339,224),'Usa a primeira regra disponível para seu level e mana.','muted',10)
for i in range(4):
    y=252+i*55;asset(im,'panel_on' if i==0 else 'panel',(338,y,466,48))
    txt(im,(349,y+13),'☑' if i==0 else '□','green' if i==0 else 'muted',13)
    small_icon(im,'healbot',(373,y+15));asset(im,'input',(402,y+13,156,22),3);txt(im,(411,y+17),'exura' if i==0 else 'Escolher magia...','text' if i==0 else 'muted',10)
    txt(im,(570,y+7),'Vida abaixo de','muted',9);asset(im,'scroll_track_h',(570,y+27,124,10),2);asset(im,'scroll_thumb_h',(645,y+27,24,10),4)
    asset(im,'input',(710,y+13,60,22),3);txt(im,(724,y+17),'70%',size=11,bold=True)
rect(d,(196,501,803,501),'edge');small_icon(im,'healbot',(198,510));txt(im,(222,511),'Bot ligado','green',11,True);txt(im,(355,512),'A prioridade segue a ordem das regras.','muted',10);btn(im,(716,508),88,'Confirmar',True)
im.save(OUT/'previews/03-heal-bot-proposta.png')

# Mythos mini-panel proposal: brand mark plus functional category icons.
im=Image.open(REF/'4-prints/pinfo.png').convert('RGBA');d=ImageDraw.Draw(im)
asset(im,'panel',(824,459,174,215));rect(d,(828,463,993,484),'title');im.alpha_composite(mythos_mark(),(830,465));txt(im,(852,465),'MYTHOS','pearl',11,True,True)
txt(im,(835,492),'CAÇA E RECOMPENSAS','gold',9,True)
for i,(name,label,value) in enumerate([('rates','Hunt Rates',''),('board','Ranking',''),('loot','Auto Loot','ON'),('tasks','Task diária',''),('trail','Trilha','6 / 50'),('healbot','Heal Bot','ON')]):
    y=511+i*25;asset(im,'panel_on' if i==0 else 'panel',(830,y,162,23));small_icon(im,name,(834,y+3));txt(im,(855,y+4),label,'text',10,True)
    if value:txt(im,(956 if value=='ON' else 950,y+4),value,'green' if value=='ON' else 'gold_hi',9,True)
im.save(OUT/'previews/06-painel-mythos-proposta.png')

# Icon comparison and full catalog; presentation scaling uses nearest-neighbor only.
small_names=['button','board','rates','tasks','trail','taskshop','bonus','rarity','loot','healbot','wiki','messages']
canvas=Image.new('RGB',(1024,660),'#11121b');txt(canvas,(32,20),'MYTHOS • ÍCONES NATIVOS',size=24,bold=True);txt(canvas,(32,60),'Esquerda: original. Direita: proposta. Ampliação apenas para inspeção.','muted',13)
for i,name in enumerate(small_names):
    x=32+(i%4)*250;y=110+(i//4)*175;fname='button.png' if name=='button' else name+'.png'
    a=Image.open(REF/'2-icones-painel'/fname).convert('RGBA');b=Image.open(OUT/'2-icones-painel'/fname)
    if name=='button':a=a.crop((0,0,20,20));b=b.crop((0,0,20,20))
    canvas.paste(a.resize((a.width*4,a.height*4),Image.Resampling.NEAREST),(x,y),a.resize((a.width*4,a.height*4),Image.Resampling.NEAREST))
    canvas.paste(b.resize((b.width*4,b.height*4),Image.Resampling.NEAREST),(x+110,y),b.resize((b.width*4,b.height*4),Image.Resampling.NEAREST))
    txt(canvas,(x,y+90),name,'pearl',12,True);txt(canvas,(x,y+112),f'{b.width} × {b.height} px • sem texto','muted',10)
canvas.save(OUT/'previews/04-icones-antes-depois.png')
files=[OUT/x['path'] for x in manifest];cols=5;cellw=280;cellh=165;rows=(len(files)+cols-1)//cols
cat=Image.new('RGB',(cols*cellw,rows*cellh+95),'#15151e');txt(cat,(20,15),'MYTHOS • OBSIDIANA REFINADA',size=24,bold=True);txt(cat,(20,53),'58 peças redesenhadas • tamanhos e bordas originais • pixel art nativa','muted',13)
for i,p in enumerate(files):
    x=(i%cols)*cellw+12;y=(i//cols)*cellh+95;im=Image.open(p);scale=min(4,210//im.width,105//im.height)
    if scale<1:scale=1;im=im.crop((0,0,im.width,min(96,im.height)))
    show=im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST)
    cat.paste(show,(x,y+35),show);txt(cat,(x,y),p.name,'pearl',11,True);txt(cat,(x,y+16),f'{manifest[i]["size"][0]}×{manifest[i]["size"][1]} · {p.parent.name}','muted',9)
cat.save(OUT/'catalogo-novo.png')

# Stress-test stretched 9-slice examples using real fixed-border contracts.
stress=Image.new('RGBA',(1100,850),rgba('#13131c'));txt(stress,(20,20),'9-SLICE • TESTE DE COMPATIBILIDADE',size=20,bold=True)
asset(stress,'window',(20,65,1050,300),6,30);txt(stress,(40,105),'Janela 1050×300 — topo 30, laterais/base 6','muted',12)
for x,w in [(45,64),(140,120),(290,220),(540,490)]:asset(stress,'button',(x,152,w,22));txt(stress,(x,183),f'{w}×22','muted',11)
for x,w in [(45,64),(140,120),(290,220),(540,490)]:asset(stress,'button_pearl',(x,212,w,22));txt(stress,(x,245),f'{w}×22','muted',11)
for x,w,h in [(20,190,150),(235,400,150),(660,410,230)]:asset(stress,'section',(x,405,w,h),4,21);txt(stress,(x+15,440),f'{w}×{h} • topo 21','muted',11)
for i,w in enumerate([120,240,480]):stress.alpha_composite(sliced(combo,(w,20),3,right=20),(20,680+i*45));txt(stress,(w+30,680+i*45),f'{w}×20 • seta fixa 20 px','muted',11)
stress.convert('RGB').save(OUT/'previews/05-teste-9-slice.png')
(OUT/'dev/manifesto.json').write_text(json.dumps({'changed_count':len(manifest),'unchanged':['3-janelas-extras/frames.png'],'assets':manifest,'validation':{'same_names':True,'same_dimensions':True,'binary_alpha':True,'state_silhouette_alignment':True,'engine_tested':False}},ensure_ascii=False,indent=2))
print('Generated',len(manifest),'compatible replacement pieces and 6 previews')
