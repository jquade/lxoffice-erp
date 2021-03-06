<html>
<LINK REL="stylesheet" HREF="../css/lx-office-erp.css" TYPE="text/css" TITLE="Lx-Office stylesheet">
<body>
<?
/*
Lieferanschriftimport mit Browser nach Lx-Office ERP

Copyright (C) 2005
Author: Philip Reetz, Holger Lindemann
Email: p.reetz@linet-services.de, hli@lx-system.de
Web: http://www.linet-services.de, http://www.lx-system.de

*/
    require ("import_lib.php");

    function ende($nr) {
        echo "Abbruch: $nr\n";
        exit($nr);
    }

    if ($_POST["ok"]=="Hilfe") {
        echo "Importfelder:<br>";
        echo "Feldname => Bedeutung<br>";
        foreach($shiptos as $key=>$val) {
            echo "$key => $val<br>";
        }
        $header=implode(";",array_keys($shiptos));
        echo $header;
        exit(0);
    };

if (!$_SESSION["db"]) {
    $conffile="../config/authentication.pl";
    if (!is_file($conffile)) {
        ende("authentication.pl nicht gefunden oder unlesbar");
    }
}

if (!anmelden()) ende("Anmeldung fehlgeschlagen");

/* get DB instance */
$db=$_SESSION["db"]; //new myDB($login);

$crm=checkCRM();

if ($_POST["ok"] == "Import") {
    $test=$_POST["test"];
    
    $shipto_fld = array_keys($shiptos);
    $shipto=$shiptos;
    
    $nun=time();

    clearstatcache ();

    $trenner=($_POST["trenner"])?$_POST["trenner"]:",";

    if (!empty($_FILES["Datei"]["name"])) { 
        $file=$_POST["ziel"];
        if (!move_uploaded_file($_FILES["Datei"]["tmp_name"],$file."_shipto.csv")) {
            $file=false;
            echo "Upload von ".$_FILES["Datei"]["name"]." fehlerhaft. (".$_FILES["Datei"]["error"].")<br>";
        } 
    } else if (is_file($_POST["ziel"]."_shipto.csv")) {
        $file=$_POST["ziel"];
    } else {
        $file=false;
    } 
    if (!$file) ende ("Kein Datenfile");

    if (!file_exists($file."_shipto.csv")) ende($file."_shipto.csv nicht im Ordner gefunden oder leer");

    $employee=chkUsr($_SESSION["employee"]);
    if (!$employee) ende("Benutzer unbekannt");

    if (!$db->chkcol($file)) ende("Importspalte konnte nicht angelegt werden");

    $f=fopen($file."_shipto.csv","r");
    $zeile=fgetcsv($f,1000,$trenner);
    $first=true;

    foreach ($zeile as $fld) {
        $fld = strtolower(trim(strtr($fld,array("\""=>"","'"=>""))));
        $in_fld[]=$fld;
    }
    $j=0;
    $n=0;
    $prenumber=$_POST["prenumber"];
    $zeile=fgetcsv($f,1000,$trenner);

    while (!feof($f)){
        $i=-1;
        $id=false;
        $sql="insert into shipto ";
        $keys="";
        $vals="";
        foreach($zeile as $data) {
            $i++;
            if (!in_array($in_fld[$i],$shipto_fld)) {
                continue;
            }
            $data=addslashes(trim($data));
            if ($in_fld[$i]=="trans_id" && $data) {
                $data=chkKdId($data);
                if (!$id) $id = $data;
                continue;
            } else  if ($in_fld[$i]=="trans_id") {
                continue;
            }
            if ($in_fld[$i]==$file."number" && $data) {
                $tmp=getFirma($data,$file);
                if ($id<>$tmp) $id=$tmp;
                continue;
            } else if ($in_fld[$i]==$file."number") {
                continue;
            }
            if ($in_fld[$i]=="firma") {
                if ($id) continue;
                $data=suchFirma($file,$data);
                if ($data) {
                    $id=$data["cp_cv_id"];
                }
                continue;
            }
            $keys.=$in_fld[$i].",";
            
            if ($data==false or empty($data) or !$data) {
                            $vals.="null,";
            } else {
                   if (in_array($in_fld[$i],array("shiptofax","shiptophone"))) {
                    $data=$prenumber.$data;
                } 
                $vals.="'".$data."',";
                // bei jedem gefuellten Datenfeld erhoehen
                $val_count++;
            }
        }
        if ($keys<>"" && $id) {
            $vals.=$id.",'CT'";
            $keys.="trans_id,module";
            if ($test) {
                if ($first) {
                    echo "<table border='1'>\n";
                    echo "<tr><th>".str_replace(",","</th><th>",$keys)."</th></tr>\n";
                    $first=false;
                };
                echo "<tr><td>".str_replace(",","</td><td>",$vals)."</td></tr>\n";
                flush();
            } else {
                $sql.="(".$keys.")";
                $sql.="values (".$vals.")";
                $rc=$db->query($sql);
                if (!$rc) echo "Fehler: ".$sql."\n";
            }
            $j++;
        } 
        $n++;
        $zeile=fgetcsv($f,1000,$trenner);
    }
    fclose($f);
    echo "</table>".$j." $file shipto von $n importiert.\n";
} else {
?>
<p class="listtop">Lieferanschriftimport f&uuml;r die ERP</p>
<form name="import" method="post" enctype="multipart/form-data" action="shiptoB.php">
<input type="hidden" name="MAX_FILE_SIZE" value="300000">
<table>
<tr><td></td><td><input type="submit" name="ok" value="Hilfe"></td></tr>
<tr><td>Zieltabelle</td><td><input type="radio" name="ziel" value="customer" checked>customer <input type="radio" name="ziel" value="vendor">vendor</td></tr>
<tr><td>Trennzeichen</td><td><input type="text" size="2" maxlength="1" name="trenner" value=";"></td></tr>
<tr><td>Telefonvorwahl</td><td><input type="text" size="4" maxlength="10" name="prenumber" value=""></td></tr>
<tr><td>Test</td><td><input type="checkbox" name="test" value="1">ja</td></tr>
<tr><td>Daten</td><td><input type="file" name="Datei"></td></tr>
<tr><td></td><td><input type="submit" name="ok" value="Import"></td></tr>
</table>
</form>
<? }; ?>
