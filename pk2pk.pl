#!/usr/bin/perl

use strict;
use warnings;
use MIME::Base64;
use Getopt::Long;
Getopt::Long::Configure ("bundling");

$|=1;

die "Usage: $0 newpk.pk\n" unless $ARGV[0];

my %uids = ();
while ( <DATA> ) {
	chomp;
	@_ = split /\t/;
	$uids{$_[1]} = $_[0];
}

my %check = ();
my $count = 0;
my %pk;
open NEW, ">$ARGV[0]";
open PK, "Finger.pk";
while ( read PK, $_, 1063 ) {
	do { my $a = $_; $a =~ s/[^[:print:]]/./g; print STDERR "$a\n\n"; } if $ENV{DEBUG};
	$check{++$count} = "0 $_";
	my $offset = 0;
	$offset = 551 if /\x77\x19\x21\x02\x00$/;
	my ($uid) = (/^.{$offset}(\w+)/);
	next unless $uid;
	$check{$count} = "0 $uid ->";
	my $newuid = $uids{$uid} || (getpwnam($uid))[0];
	next unless $newuid;
	$check{$count} = "0 $uid -> $newuid";
	if ( $newuid ne $uid ) {
		if ( length($uid) > length($newuid) ) {
			$newuid .= "\000" x (length($uid) - length($newuid));
		}
		substr($_, $offset, length($newuid), $newuid);
	}
	$check{$count} = "1 $uid -> $newuid";
	delete $uids{$uid};
	print NEW;
}
close PK;
close NEW;

#print "ALL\n";
#foreach my $count ( sort { $a <=> $b } keys %check ) {
#	print "$count: $check{$count}\n";
#}
#exit;
print "FAILED\n"; my $c = 0;
foreach my $count ( sort { $a <=> $b } keys %check ) {
	$check{$count} =~ s/[^[:print:]]/./g;
	next unless $check{$count} =~ s/^0$|^0\s+//;
	print "$count: $check{$count}\n";
	$c++;
}
print "FAILED: $c\n";

print "\nSUCCEEDED\n"; $c = 0;
foreach my $count ( sort { $a <=> $b } keys %check ) {
	next unless $check{$count} =~ s/^1\s+//;
	print "$count: $check{$count}\n";
	$c++;
}
print "SUCCEEDED: $c\n";

print "\nNOT FOUND\n"; $c = 0;
foreach my $uid ( sort keys %uids ) {
	print "x: $uid -> $uids{$uid}\n";
	$c++;
}
print "NOT FOUND: $c\n";

__DATA__
AHOLTNIC000	aholtni
ALFERBET000	alfermannb
ALFERJAM000	alfermanj
ALFERWES000	alfermannw
ANDERBLA000	andersonb
APPRIBRI000	apprillb
BAKERCOL000	bakerc
BALDUNAT001	balduccin
BARRIANT000	barringhausa
BARROTHO000	barrowt
BAUMSJOH000	baumstarkj
BAYLAALE000	baylarda
BEAN_BRI000	beanb
BECKEAND002	beckermana
BELL_ABI000	bella
BIELIDYL000	bielicked
BIERMKAT000	biermannk
BISHOEMI000	bishope
BITTIWAY000	bittickw
BITZEBRI000	bitzerb
BLATTCAR000	blattc
BLECHALE000	blechlea
BLUMEAMB000	blumenfelda
BOHLEALE000	bohlea
BOLANKAT000	bolandka
BOLANSAM001	bolandsa
BOLANTED000	bolandt
BOLTEKAT000	boltek
BOMANJOS000	bomanj
BORESJES000	boresij
BORGENOA000	borgerdingn
BOUSEABB000	bousea
BOWMAADA000	bowmana
BOWMAEMI000	bowmane
BRANSKYL000	bransonk
BRAUNSAR000	brauns
BRECKKEL000	breckenkampk
BREHEKAI000	brehek
BREIGAAR000	breiga
BRICKTAY000	brickeyt
BRIGHCAI000	brightc
BRINKELE000	brinke
BRINKMAD000	brinkmannm
BRINKRAC000	brinkerra
BRINKRYA000	brinkerr
BROMETHO000	bromeiert
BUCHMMAG000	buchmannm
BUHR_ELI000	buhre
BURGESTE000	burgesss
BUSCHALE000	buschmana
CALVEJAC000	calvertj
CARR_IAN000	carri
CARR_MCK000	carrm
CARRITHO000	carricot
CHALKBRE000	chalkb
CHENGKAR000	chengka
CHENGKEN000	chengk
CIBULKAT000	cibulkak
CLEMOHAN000	clemonsh
CONROCOL000	conroyc
CONWALAN000	conwayl
COOK_COL000	cookco
COOK_MAR000	cookm
CORMIMAR000	cormierm
DEMPSKRI000	dempseyk
DEPPEKYL000	deppermannk
DESCHMIC000	deschenesm
DESCHSAM000	descheness
DIENEMAR001	dienerma
DIENERAC000	dienerr
DIENEVAL000	dienerv
DIERKBEN000	dierkerb
DIERMJES000	diermannje
DOBSCKAI000	dobschk
DOBSCMAT000	dobschm
DOLANBRY000	dolanb
DONNEJES000	donnellyj
DORSEDAN000	dorseyd
DORTOALE000	dortona
DUFF_JAC000	duffj
DULANSYD000	dulanys
DURBIRYA000	durbinr
DUTTOBRA000	duttonb
ECKELASH001	eckelkampa
ECKELGRA000	eckelkampg
ECKELJOS000	eckelkampjo
EGGERANT000	eggerta
EGGERNIC000	eggertn
EGGERSHA000	eggerts
ELBERBRE000	elbertb
ELJAIALE000	eljaieka
ELJAICHR000	eljaiekc
ELLEFWHI000	ellefsonw
EMKE_EMM000	emkee
EMKE_KAI000	emkek
EMMENMAR000	emmendorferm
ENGERJOS000	engerj
ESCHBLIS000	eschbacherli
FELDMBRE000	feldmannbr
FILLARIV000	fillar
FINDETHO000	findeisst
FISCHANN000	fischera
FISCHBAI000	fischerba
FISTEJOS000	fisterj
FITZPKRI000	fitzpatrickk
FOX__MIC000	foxm
FRIENABI000	frienda
FRITZGRA000	fritzgr
FRY__MIL000	frymi
FRYE_GAR000	fryeg
GALATCHL000	galatic
GARDNCOD000	gardnerc
GEATLLUK000	geatleyl
GIBSOMAG000	gibsonm
GIBSONAT000	gibsonna
GIERECAR001	giererc
GILDEDAV000	gildehausda
GILDEDOM000	gildehausdo
GILLEBRI000	gilletteb
GISBUKYL000	gisburnek
GLASTEMA000	glastettere
GLASTHAN000	glastetterh
GLOSERYA000	glosemeyerr
GRAEFKAY000	graefk
GRAHAABI000	grahama
GRAHAJUS000	grahamju
GRAHAMAR001	grahamm
GRAHLDAV000	grahld
GRELLMEG000	grellnerm
GRIMMHAN000	grimmh
GROGATYL000	grogant
GUBBEAMA000	gubbelsa
GUBBEELI000	gubbelse
HABERBLA000	haberbergebl
HADDOJOH000	haddoxj
HADDOJOS000	haddoxjo
HADDOMAC000	haddoxm
HADDONIC000	haddoxn
HALSTCOR000	halstedc
HAM__KAY000	hamk
HANNEMAR003	hannekenm
HARTIKAI000	hartigk
HASKIJAC000	haskinsja
HASKIKAT001	haskinsk
HASSLETH000	elbere
HEARSDAN000	hearstd
HELFRABA000	helfrichab
HELFRANT000	helfricha
HELLEJEN000	hellebuschje
HELLEJOD000	hellebuschj
HELLMELI000	hellmanne
HILLEERI001	hillermane
HIMMENAT000	himmelbergn
HINTEGAB000	hinterlongg
HOEMANAD000	hoemannn
HOERSTAY000	hoerstkampt
HOEY_STE000	hoeys
HOGENRYA000	hogenmillerr
HOLTMBEN000	holtmeyerb
HOLTMHAN000	holtmeyerh
HOLTMMAR002	holtmeierm
HOLZENIC000	holzemn
HOPKIBRI000	hopkinsb
HORACTYL000	horacet
HOWARERI000	howarde
HOWARRAV000	howardr
HOWELIAN000	howelli
HOWELTYL000	howellt
HOWELZAC000	howellz
HUBERAMY000	hubera
HUBERDOM000	huberd
HUBERSAM000	hubers
HULCEABB000	hulcera
HURTIANT000	hurtian
HURTIAUS000	hurtigau
HUXELTRI000	huxelt
JACKSSTE000	jacksons
JACQUNIC000	jacquinn
JASPEALE000	jaspera
JASPEBRA001	jasperb
JOHNSEVA000	johnsone
JONESBRE000	jonesb
JUDGEGRE000	judgeg
KAMPSDUS000	kampschroederd
KANG_ELE000	kange
KENNYLAU000	kennyl
KIMMIDRE000	kimminaud
KIMMIPAT000	kimminaup
KING_ERI000	kinge
KLEEKBRE001	kleekampbr
KLEEKJAC000	kleekampj
KLEEKKRI000	kleekampk
KLEEKPHI001	kleekampp
KLEEKTYL000	kleekampt
KLEKAAND000	klekampa
KLOTTJOD000	klottjod
KLUESJOS000	kluesnerj
KOENEROB000	koenemannro
KONCZEMI000	konczale
KONCZMIC002	konczalm
KOPMAJAC000	kopmannj
KRAMPDAN000	kramped
KREN_MIC001	krenm
KRUELJOS000	kruelj
KUCHEAND000	kucheman
KUCHECAS000	kuchemc
LABEAKYL000	labeauk
LADIGJUS000	ladigj
LANDWABI000	landwehrab
LANDWALY000	landwehra
LANGEKEL000	langenbergk
LAUSEAMB000	lauseam
LAUSEANT000	lausea
LEBSACON000	lebsackc
LEESMJUL000	leesmannj
LEIMKTRE000	leimkuehlert
LEOPOROS000	leopoldr
LEYKAJOR000	leykamj
LINDEKAT000	lindemannk
LONG_JAC000	longj
LONIGLUK000	lonigrol
LYNN_DAL000	lynnd
MALLIHEA000	mallinckrodth
MANETJEN000	manetzj
MANETREB000	manetzr
MANTLKEL000	mantlek
MARQUPRE000	marquartp
MARQUTAY000	marquartt
MARQUWIL002	marquartw
MATHERYA000	mathewsr
MAUNERYA000	mauner
MAUNTKEL000	mauntelk
MAXWEKAT000	maxwellka
MAYERBRA000	mayerb
MAYORSAR000	mayorals
MEE__MIC000	meemi
MEINEJOS000	meinertj
MENTZTAY000	mentzt
MEYERGEO000	meyerg
MEYERMEL001	meyerm
MILLEHAN000	millerh
MILLEJOR000	millerj
MILLIDAN000	millickd
MOHESJAR000	moheskyj
MOHRLJOS000	mohrlockj
MONROJAM000	monroej
MONZYNIC000	monzykni
MOOREKAT000	moorek
MORONCAI000	moroneyc
MORONPAT000	moroneyp
NEIERAAR000	neiera
NEIERELL000	neiere
NEWBAJOS000	newbanksj
NOELKABI000	noelkea
NOELKKAI000	noelkerk
NOELKMAT000	noelkerm
NOLTEKOR000	noltek
NOVAKROB001	novakr
OBERMAND000	obermarka
OBERMMOL000	obermarkm
OLIMPJOH000	olimpioj
ORTMAJAM000	ortmannj
OVERSALE000	overschmidtal
PAK__LIY000	pakl
PATKEKIM000	patkek
PERROGAR000	perrottog
PEZOLCLA000	pezoldc
PEZOLJAC000	pezoldj
PIONTAAR000	piontekaa
PIONTALE000	piontekal
PIONTCOL000	piontekc
PIONTKEL000	piontekk
PIONTMAD000	piontekm
PIONTSHA000	pionteks
POEPSHAL000	poepselh
POLITKAT000	polittek
POST_HAN000	posth
PRESSDEN000	pressond
PRIESSAM000	priesters
PRITCJAM000	pritchardj
RATCLANA000	ratcliffa
REID_MEG000	reidm
REIDYMEG000	reidym
REMBECLA000	rembeckic
RETTKAUS000	rettkeau
RHYNEJOS000	rhynej
RIKARJEN000	rikardj
RIKARRIA000	rikardr
RILEYMAT000	rileyma
RION ZAC000	rionz
RION_ELI000	rione
RITTEMIC000	ritterm
ROACHKRI000	roachk
ROACHLAU000	roachl
ROEHRAND000	roehriga
ROEHRMOR000	roehrigmo
ROGERNAT000	rogersn
ROLOFROB000	roloffr
ROUBIJOA000	roubianj
RUDLOSAM000	rudloffs
RUETHAND000	ruethera
RUETHBEN000	ruetherb
RUSSEHAL000	russellh
RYAN_EMI000	ryanem
SANDEJAC000	sanderj
SAUERDAN000	sauerd
SCHEIELI000	scheiblee
SCHMIADA001	schmitta
SCHOPBRI000	schoppenhorstb
SCHRILUK000	schriewerl
SCHROCLA000	schroederc
SCHUCADA000	schuckmanna
SCHWEHAN000	schweissguthh
SCHWOKAT000	schwoeppek
SEARCALE000	searcya
SELIGJOH000	seligajo
SEMONGID000	semonesg
SEVERALE000	severinoa
SHERFLEI000	sherfeyl
SHIPLEMI000	shipleye
SIEBENAT000	siebertn
SIEVEBRI000	sieveb
SIMMOREA000	simmonsr
SISCOEMI000	siscoe
SITESABI000	sitesa
SKAGGCHR000	skaggsc
SKUBISYD000	skubics
SMITHALE000	smitha
SMITHDAN001	smithda
SMITHJAR000	smithj
SMITHJEN000	smithjen
SMITHJES001	smithje
SMITHRAY000	smithr
SMITHVIC000	smithv
SOHN_BRI000	sohnb
SPAUNDAV000	spaunhorstd
SPRADMOR000	spradlingm
STALLWIL000	stallmannw
STAMMOLI000	stammingero
STAMMRIC000	stammingerr
STEINBRY000	steinbeckb
STELZBEN000	stelzerb
STEWAJAC000	stewartj
STORTZAC000	stortzz
STRAAANT000	straatmana
STRAAEDW000	straatmanne
STRAAPAI000	straatmannp
STRAUBRE000	strauserbr
STRAUJON000	strauserj
STRUCALE000	struckhoffa
STRUCJEN001	struckhoffj
STRUCKRI000	struckhoffk
STRUCMAR002	struckhoffm
SULLICHR000	sullivanch
SULLIIAN000	sullivani
SUTTOAND000	suttona
SWARTWHI000	swartzw
SWOBOANN000	swobodaan
SWOBOJUL000	swobodaj
THOMAKAT000	thomask
TIMPEPHI000	timpep
TITTEALI000	tittera
TITTEKAI000	titterk
TOBBEMAD000	tobbenma
TOBBEMOR000	tobbenm
TONEYEMI000	toneye
TULLEDAN001	tulleyd
TULLEGAB000	tulleyg
UNERSOLI000	unerstallo
UNNERCLA000	unnerstallc
UNNERMON000	unnerstallm
VEHIGWHI000	vehigew
VENARALE000	venardosa
VINSOANG000	vinsona
VIVIAPHI000	vivianop
VOSS_CON000	vossc
VOSS_KAT000	vossk
VOSSBROB001	vossbrinkr
WALDECHA000	waldec
WALDEGRA000	waldeg
WALDEZAC000	waldez
WALLAANN000	wallacea
WALLSNIC000	wallsn
WALSHBRI000	walshb
WEBERTIM000	webert
WEHKIMAD000	wehkingm
WEHNEBEN000	wehnerb
WEHNENIC000	wehnern
WESTHDEA000	westhoffde
WILD_ELI000	wilde
WILLEKAT000	willenbrinkk
WILMEKAR000	wilmesherk
WILMOJUL000	wilmothj
WILMOMEL000	wilmothm
WILSODEA000	wilsond
WILSOGLE000	wilsong
WILSOPEY000	wilsonp
WINKEKAI000	winkelmannk
WOOLEJAC000	wooleyj
WUNDEMEG000	wunderlichm
YENZEABI000	yenzera
YENZEIAN000	yenzeri
YENZEKAT001	yenzerk
ZEITZEVA000	zeitzmanne